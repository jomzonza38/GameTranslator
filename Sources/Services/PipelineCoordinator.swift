import Foundation
import CoreGraphics
import AppKit
import Combine

/// Coordinates the full translation pipeline:
/// Screen Capture → OCR → Text Diff → Translation → Overlay
@MainActor
final class PipelineCoordinator: ObservableObject {
    // MARK: - Published State

    @Published var isRunning = false
    @Published var status: PipelineStatus = .idle
    @Published var currentRegions: [TranslatedRegion] = []
    @Published var lastError: String?
    @Published var stats = PipelineStats()

    // MARK: - Services

    private let screenCapture = ScreenCaptureService()
    private let ocrService = OCRService()
    private let translationService: TranslationService
    private let overlayController: OverlayWindowController
    private let panelController: TranslationPanelController
    private let regionSelector = RegionSelectorWindow()

    // MARK: - Per-Region Pipeline State

    /// Pipeline state for full-screen mode (no regions defined)
    private let globalState = RegionPipelineState()

    /// Pipeline state per capture region, keyed by region UUID
    private var regionStates: [UUID: RegionPipelineState] = [:]

    // MARK: - State

    private var selectedWindow: Any? // SCWindow
    private var pendingFrame: (image: CGImage, contentRect: CGRect)?
    private var isProcessing = false
    /// The running drain loop, cancelled by stop()
    private var pipelineTask: Task<Void, Never>?
    /// Moved on by every start and teardown, so a start that finishes after the user
    /// stopped (or started again) leaves the current state alone
    private var sessions = StartGeneration()
    private let settings = AppSettings.shared

    /// Callback when capture regions change (add/remove/clear)
    var onRegionsChanged: (() -> Void)?

    /// Callback after capture ended on its own (game window closed) and the
    /// session was torn down, so the menu and status icon can refresh
    var onStoppedUnexpectedly: (() -> Void)?

    /// Recent lines and glossary sent to LLM providers
    private let contextBuilder = TranslationContextBuilder()

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        self.translationService = TranslationService()
        self.overlayController = OverlayWindowController()
        self.panelController = TranslationPanelController()

        screenCapture.delegate = self
        ocrService.minimumConfidence = settings.minimumConfidence

        // When a region is switched off (or deleted), remove its translations from
        // the screen right away — even while paused — and let the menu refresh.
        settings.$captureRegions
            .dropFirst()
            .sink { [weak self] regions in
                Task { @MainActor in
                    self?.applyRegionVisibility(regions)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Control

    func start(window: Any) async throws {
        guard !isRunning else { return }

        // Always refresh provider to pick up the latest API key
        updateProvider()

        // Validate API key before starting capture
        if settings.selectedProvider.requiresApiKey && !hasApiKey(for: settings.selectedProvider) {
            throw TranslationError.missingApiKey
        }

        guard let scWindow = window as? SCWindow else {
            throw PipelineError.invalidWindow
        }

        // Per-game profile (title, glossary) keyed by the game's app name
        settings.selectGame(id: scWindow.owningApplication?.applicationName ?? scWindow.title ?? "Unknown")
        contextBuilder.reset(glossary: settings.currentProfile.glossary)

        let session = sessions.begin()
        selectedWindow = window
        isRunning = true
        status = .capturing
        lastError = nil
        stats = PipelineStats()
        globalState.reset()
        regionStates.removeAll()

        // Initialize per-region states
        for region in settings.captureRegions {
            regionStates[region.id] = RegionPipelineState()
        }

        // Show overlay or panel based on display mode
        if settings.displayMode == .overlay {
            overlayController.show(over: scWindow.frame)
        } else {
            panelController.show(near: scWindow.frame)
        }
        GameLog.log("Starting capture of window: \(scWindow.title ?? "unknown") (\(Int(scWindow.frame.width))x\(Int(scWindow.frame.height)))")
        GameLog.log("Provider: \(translationService.currentProviderName), FPS: \(settings.captureFrameRate)")
        GameLog.log("Capture regions: \(settings.captureRegions.count) defined")

        // Start screen capture. If it fails (e.g. the game window closed after it
        // was picked), undo everything above so the app is idle again.
        do {
            try await screenCapture.startCapture(
                window: scWindow,
                frameRate: settings.captureFrameRate
            )
        } catch {
            // Stopped (or restarted) while starting: that stop already cleaned up and
            // may have begun a new session — leave it alone, and don't show an error
            guard sessions.isCurrent(session) else {
                GameLog.log("Start was stopped before capture began")
                return
            }
            GameLog.log("✗ Capture failed to start: \(error.localizedDescription)")
            await tearDown()
            lastError = error.localizedDescription
            throw error
        }

        // Stopped right after capture started — teardown already stopped the stream
        guard sessions.isCurrent(session) else { return }

        GameLog.log("✓ Capture started successfully")
        status = .running
    }

    func stop() async {
        guard isRunning else { return }
        await tearDown()
    }

    /// Capture ended without the user stopping it — clean up like a normal stop
    /// and leave a Thai message in the menu. Uses no alert: the user is often busy
    /// restarting the game, so nothing should block or steal focus.
    private func handleUnexpectedStop(_ reason: CaptureStopReason) async {
        guard isRunning else { return }

        let message: String
        switch reason {
        case .windowClosed:
            GameLog.log("✗ Game window closed — stopping translation")
            message = "หยุดแปลแล้ว เพราะหน้าต่างเกมถูกปิด"
        case .streamFailed(let error):
            GameLog.log("✗ Capture stopped unexpectedly: \(error.localizedDescription) — stopping translation")
            message = "หยุดแปลแล้ว เพราะการจับภาพหยุดทำงาน: \(error.localizedDescription)"
        }

        await tearDown()
        lastError = message
        onStoppedUnexpectedly?()
    }

    /// Return to the idle state: used by stop() and when start() fails part-way
    private func tearDown() async {
        sessions.invalidate()
        isRunning = false

        // Drop queued frames and stop the in-flight pipeline, so nothing is
        // translated, added to history or drawn after stopping
        pipelineTask?.cancel()
        pipelineTask = nil
        pendingFrame = nil

        await screenCapture.stopCapture()
        overlayController.hide()
        panelController.hide()

        status = .idle
        currentRegions = []
        selectedWindow = nil
    }

    func updateProvider() {
        translationService.switchProvider(to: settings.selectedProvider)
    }

    /// Switch between overlay and panel display modes while running
    func switchDisplayMode() {
        guard isRunning, let window = selectedWindow as? SCWindow else { return }

        if settings.displayMode == .overlay {
            // Switching to overlay mode
            panelController.hide()
            overlayController.show(over: window.frame)
            if let windowFrame = screenCapture.currentWindowFrame {
                overlayController.updateRegions(currentRegions, windowFrame: windowFrame)
            }
        } else {
            // Switching to panel mode
            overlayController.hide()
            panelController.show(near: window.frame)
            panelController.updateRegions(currentRegions)
        }
    }

    // MARK: - Multi-Region Management

    /// Show the region selector and add a new capture region
    func addCaptureRegion(name: String, color: RegionColor) {
        guard let window = selectedWindow as? SCWindow else { return }
        let windowFrame = screenCapture.currentWindowFrame ?? window.frame

        // Temporarily hide overlay so it doesn't interfere with region selection
        overlayController.hideTemporarily()

        regionSelector.show(over: windowFrame, color: color) { [weak self] normalizedRect in
            guard let self = self else { return }
            Task { @MainActor in
                let region = CaptureRegion(name: name, rect: normalizedRect, color: color)
                self.settings.addRegion(region)
                self.regionStates[region.id] = RegionPipelineState()

                GameLog.log("Region added: \(name) (\(color.rawValue)) x=\(String(format: "%.2f", normalizedRect.origin.x)) y=\(String(format: "%.2f", normalizedRect.origin.y)) w=\(String(format: "%.2f", normalizedRect.width)) h=\(String(format: "%.2f", normalizedRect.height))")

                // Re-show overlay if in overlay mode
                if self.settings.displayMode == .overlay, self.isRunning {
                    self.overlayController.show(over: windowFrame)
                }

                self.onRegionsChanged?()
            }
        }
    }

    /// Remove a specific capture region
    func removeCaptureRegion(id: UUID) {
        settings.removeRegion(id: id)
        regionStates.removeValue(forKey: id)
        GameLog.log("Region removed: \(id)")
        onRegionsChanged?()
    }

    /// Clear all capture regions — translate the whole window again
    func clearAllCaptureRegions() {
        settings.removeAllRegions()
        regionStates.removeAll()
        globalState.reset()
        GameLog.log("All capture regions cleared — translating full window")
        onRegionsChanged?()
    }

    /// Show/hide one region's translations (without deleting the region)
    func toggleCaptureRegion(id: UUID) {
        settings.toggleRegion(id: id)
        if let region = settings.captureRegions.first(where: { $0.id == id }) {
            GameLog.log("Region \(region.name) \(region.isEnabled ? "shown" : "hidden")")
        }
    }

    /// Drop on-screen boxes that belong to regions that are now off or deleted
    private func applyRegionVisibility(_ regions: [CaptureRegion]) {
        let enabledIDs = Set(regions.filter(\.isEnabled).map(\.id))
        let visible = currentRegions.filter { region in
            guard let id = region.regionID else { return regions.isEmpty }
            return enabledIDs.contains(id)
        }
        if visible.count != currentRegions.count {
            currentRegions = visible
            if isRunning, let windowFrame = screenCapture.currentWindowFrame {
                if settings.displayMode == .overlay {
                    overlayController.updateRegions(visible, windowFrame: windowFrame)
                } else {
                    panelController.updateRegions(visible)
                }
            }
        }
        onRegionsChanged?()
    }

    /// Check whether the current provider has its API key configured
    private func hasApiKey(for provider: AppSettings.TranslationProviderType) -> Bool {
        switch provider {
        case .googleFree: return true
        case .openAI: return !settings.openAIApiKey.isEmpty
        case .claudeHaiku: return !settings.claudeApiKey.isEmpty
        case .deeplFree, .deeplPro: return !settings.deeplApiKey.isEmpty
        case .googleCloud: return !settings.googleCloudApiKey.isEmpty
        }
    }

    // MARK: - Pipeline Processing

    private func processFrame(_ image: CGImage, contentRect: CGRect) {
        guard isRunning else { return }
        guard !isProcessing else {
            pendingFrame = (image, contentRect)
            return
        }

        // Claim the pipeline now, not inside the Task: frames already queued on the
        // main actor would otherwise each start their own pipeline before it runs
        isProcessing = true
        pipelineTask = Task { [weak self] in
            await self?.drainPipeline(image: image, contentRect: contentRect)
        }
    }

    private func drainPipeline(image: CGImage, contentRect: CGRect) async {
        var next: (image: CGImage, contentRect: CGRect)? = (image, contentRect)

        while let frame = next, !Task.isCancelled {
            await runPipeline(image: frame.image, contentRect: frame.contentRect)
            next = pendingFrame
            pendingFrame = nil
        }
        isProcessing = false
    }

    /// How long to wait before retrying a text whose translation request failed
    private let retryDelay: CFAbsoluteTime = 3

    /// One region's intermediate results for the current frame
    private struct RegionFrameWork {
        let state: RegionPipelineState
        let regionColor: RegionColor?
        let regionName: String?
        let regionID: UUID?
        /// Texts on screen in this region (after line merging), in reading order
        let currentTexts: [DetectedText]
        /// Texts that need an API translation this frame
        let textsToTranslate: [String]
    }

    private func runPipeline(image: CGImage, contentRect: CGRect) async {
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        await applyGlossaryChangesIfNeeded()

        do {
            // Step 1: OCR settings
            // Pick up the latest OCR settings every frame so changes apply while running
            ocrService.minimumConfidence = settings.minimumConfidence
            ocrService.recognitionLevel = settings.effectiveOCRAccuracy == .accurate ? .accurate : .fast
            ocrService.recognitionLanguages = settings.sourceLanguage.visionLanguages
            ocrService.minimumTextLength = settings.sourceLanguage.usesWordSpacing ? 2 : 1

            let imageSize = CGSize(width: image.width, height: image.height)
            let windowFrame = screenCapture.currentWindowFrame ?? contentRect
            let captureRegions = settings.captureRegions
            let ocrStart = CFAbsoluteTimeGetCurrent()
            var textsDetected = 0

            // Step 2: per region — OCR, merge lines, diff, reuse known translations
            var works: [RegionFrameWork] = []
            if captureRegions.isEmpty {
                // No regions — read the whole window
                let ocrFrame = try await ocrService.recognizeText(in: image, imageSize: imageSize)
                textsDetected += ocrFrame.texts.count
                works.append(prepareRegion(
                    ocrFrame: ocrFrame, filterRegion: nil, regionColor: nil, regionName: nil,
                    regionID: nil, state: globalState,
                    ocrTime: CFAbsoluteTimeGetCurrent() - ocrStart
                ))
            } else {
                // OCR only the pixels inside each enabled region, so nothing outside
                // the frame can be read. Disabled regions are skipped entirely.
                for captureRegion in captureRegions where captureRegion.isEnabled {
                    let state: RegionPipelineState
                    if let existing = regionStates[captureRegion.id] {
                        state = existing
                    } else {
                        state = RegionPipelineState()
                        regionStates[captureRegion.id] = state
                    }

                    let regionOCRStart = CFAbsoluteTimeGetCurrent()
                    let ocrFrame = try await ocrService.recognizeText(
                        in: image,
                        imageSize: imageSize,
                        cropTo: captureRegion.rect
                    )
                    textsDetected += ocrFrame.texts.count

                    works.append(prepareRegion(
                        ocrFrame: ocrFrame, filterRegion: captureRegion.rect,
                        regionColor: captureRegion.color, regionName: captureRegion.name,
                        regionID: captureRegion.id, state: state,
                        ocrTime: CFAbsoluteTimeGetCurrent() - regionOCRStart
                    ))
                }
            }
            let ocrTime = CFAbsoluteTimeGetCurrent() - ocrStart
            guard isRunning, !Task.isCancelled else { return }

            // Step 3: one translation request for every region together
            let translateStart = CFAbsoluteTimeGetCurrent()
            await translatePending(works)
            let translateTime = CFAbsoluteTimeGetCurrent() - translateStart
            guard isRunning, !Task.isCancelled else { return }

            // Step 4: cache bookkeeping and on-screen boxes per region
            var allTranslatedRegions: [TranslatedRegion] = []
            for work in works {
                finishRegion(work)
                allTranslatedRegions += RegionLayout.buildRegions(
                    from: work.currentTexts,
                    windowFrame: windowFrame,
                    options: layoutOptions,
                    regionColor: work.regionColor,
                    regionName: work.regionName,
                    regionID: work.regionID,
                    translation: work.state.translation(for:)
                )
            }

            // Step 5: Resolve overlapping regions — push colliding boxes down
            let resolvedRegions = RegionLayout.resolveOverlaps(allTranslatedRegions, options: layoutOptions)

            // Step 6: ALWAYS update display (overlay or panel)
            currentRegions = resolvedRegions
            if settings.displayMode == .overlay {
                overlayController.updateRegions(resolvedRegions, windowFrame: windowFrame)
            } else {
                panelController.updateRegions(resolvedRegions)
            }

            // Update stats
            let totalTime = CFAbsoluteTimeGetCurrent() - pipelineStart
            stats.update(
                ocrTime: ocrTime,
                translateTime: translateTime,
                totalTime: totalTime,
                textsDetected: textsDetected,
                textsTranslated: allTranslatedRegions.count
            )
        } catch {
            guard !Task.isCancelled else { return }
            GameLog.log("✗ Pipeline error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Filter the frame to one region (or full screen when `filterRegion` is nil),
    /// diff it with the previous frame, and decide which texts need an API call.
    private func prepareRegion(
        ocrFrame: OCRFrame,
        filterRegion: CGRect?,
        regionColor: RegionColor?,
        regionName: String?,
        regionID: UUID?,
        state: RegionPipelineState,
        ocrTime: Double
    ) -> RegionFrameWork {
        // Filter by region (if specified)
        let filteredFrame: OCRFrame
        if let region = filterRegion {
            let filtered = ocrFrame.texts.filter { text in
                // Use center-point containment instead of intersects to avoid
                // picking up text that barely touches the region edge.
                let center = CGPoint(x: text.boundingBox.midX, y: text.boundingBox.midY)
                return region.contains(center)
            }
            filteredFrame = OCRFrame(texts: filtered, imageSize: ocrFrame.imageSize)
        } else {
            filteredFrame = ocrFrame
        }

        // Merge adjacent lines
        let mergedFrame = RegionLayout.mergeAdjacentLines(
            filteredFrame,
            separator: settings.sourceLanguage.usesWordSpacing ? " " : ""
        )

        // Only log when the detected-text count changes
        if mergedFrame.texts.count != state.lastLoggedTextCount {
            state.lastLoggedTextCount = mergedFrame.texts.count
            let label = regionName ?? "full-screen"
            GameLog.log("OCR [\(label)]: \(mergedFrame.texts.count) texts in \(String(format: "%.0f", ocrTime * 1000))ms")
        }

        // Diff with previous frame
        let diffResult = state.textTracker.diff(currentFrame: mergedFrame)

        // Detect rapid content change (scrolling/page navigation)
        let totalVisible = diffResult.unchangedTexts.count + diffResult.newTexts.count + diffResult.changedTexts.count
        let removedCount = diffResult.removedTexts.count
        if removedCount > 2 && totalVisible > 0 {
            let changeRatio = Double(removedCount) / Double(removedCount + totalVisible)
            if changeRatio > 0.4 {
                for removed in diffResult.removedTexts {
                    state.cachedTranslations.removeValue(forKey: removed.text)
                }
            }
        }

        let currentTexts = (diffResult.unchangedTexts + diffResult.newTexts + diffResult.changedTexts.map(\.new))
            .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        let unchanged = Set(diffResult.unchangedTexts.map(\.text))
        let now = CFAbsoluteTimeGetCurrent()

        var textsToTranslate: [String] = []
        for detected in currentTexts {
            let text = detected.text
            if state.cachedTranslations[text] != nil { continue }

            // Came back on screen within the grace period
            if let stale = state.staleTranslations.removeValue(forKey: text) {
                state.cachedTranslations[text] = stale.translation
                continue
            }

            // Exactly a glossary term — fixed translation, no API call
            if let fixed = contextBuilder.fixedTranslation(for: text) {
                state.cachedTranslations[text] = fixed
                continue
            }

            // Same line as before with a misread letter — keep the existing translation
            // so the text on screen doesn't change and doesn't need to be re-read
            if unchanged.contains(text), let similar = state.similarTranslation(for: text) {
                state.cachedTranslations[text] = similar
                continue
            }

            // Wait until the text stops changing (typewriter effect, fade-in)
            guard state.isStable(text) else { continue }

            // Back off after a failed request instead of retrying every frame
            if let failed = state.failedAt[text], now - failed < retryDelay { continue }

            if !textsToTranslate.contains(text) {
                textsToTranslate.append(text)
            }
        }

        state.previousFrameTexts = currentTexts.map(\.text)

        return RegionFrameWork(
            state: state,
            regionColor: regionColor,
            regionName: regionName,
            regionID: regionID,
            currentTexts: currentTexts,
            textsToTranslate: textsToTranslate
        )
    }

    /// Translate what every region needs in a single request
    private func translatePending(_ works: [RegionFrameWork]) async {
        var texts: [String] = []
        for work in works {
            for text in work.textsToTranslate where !texts.contains(text) {
                texts.append(text)
            }
        }
        guard !texts.isEmpty else { return }

        let labels = works.filter { !$0.textsToTranslate.isEmpty }.map { $0.regionName ?? "full-screen" }
        GameLog.log("Translating \(texts.count) texts via \(translationService.currentProviderName) [\(labels.joined(separator: ", "))]...")

        do {
            let translations = try await translationService.translateBatch(
                texts,
                context: contextBuilder.context(
                    for: texts,
                    sourceLanguageName: settings.sourceLanguage.englishName,
                    gameTitle: settings.currentProfile.title,
                    includeRecentLines: settings.useConversationContext
                )
            )

            // Stopped while waiting — don't record anything for a finished session
            guard !Task.isCancelled else { return }

            // Iterate in on-screen order so the context reads naturally
            for text in texts {
                guard let translation = translations[text] else { continue }
                for work in works where work.textsToTranslate.contains(text) {
                    work.state.cachedTranslations[text] = translation
                    work.state.failedAt.removeValue(forKey: text)
                }
                contextBuilder.remember(original: text, translation: translation)
                TranslationHistory.shared.add(
                    original: text,
                    translation: translation,
                    game: settings.currentProfile.title
                )
                GameLog.log("\u{2713} \"\(text)\" \u{2192} \"\(translation)\"")
            }
            lastError = nil
        } catch {
            // The request was cancelled by stop() — not a real failure
            guard !Task.isCancelled else { return }
            let now = CFAbsoluteTimeGetCurrent()
            for work in works {
                for text in work.textsToTranslate {
                    work.state.failedAt[text] = now
                }
            }
            GameLog.log("\u{2717} Translation error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Move translations of texts that left the screen to the stale cache (10 s grace period)
    private func finishRegion(_ work: RegionFrameWork) {
        let state = work.state
        let now = CFAbsoluteTimeGetCurrent()
        let onScreen = Set(work.currentTexts.map(\.text))

        for (text, translation) in state.cachedTranslations where !onScreen.contains(text) {
            state.cachedTranslations.removeValue(forKey: text)
            state.staleTranslations[text] = (translation, now + 10)
        }
        state.staleTranslations = state.staleTranslations.filter { $0.value.expiry > now }
        state.failedAt = state.failedAt.filter { now - $0.value < 60 }
    }

    // MARK: - Layout

    private var layoutOptions: RegionLayout.Options {
        RegionLayout.Options(
            autoFontSize: settings.autoFontSize,
            fixedFontSize: settings.overlayFontSize,
            showOriginalText: settings.showOriginalText
        )
    }

    // MARK: - Glossary & Caches

    /// Apply glossary edits once they settle, re-translating on-screen text
    private func applyGlossaryChangesIfNeeded() async {
        let glossary = settings.currentProfile.glossary
        guard contextBuilder.updateGlossary(glossary, now: CFAbsoluteTimeGetCurrent()) else { return }
        await resetTranslationCaches()
        GameLog.log("Glossary updated (\(contextBuilder.appliedGlossary.count) terms) — re-translating on-screen text")
    }

    /// Forget all cached translations so visible text is translated again
    func resetTranslationCaches() async {
        globalState.reset()
        for state in regionStates.values {
            state.reset()
        }
        contextBuilder.clearRecentLines()
        await translationService.clearCache()
    }
}

// MARK: - ScreenCaptureDelegate

extension PipelineCoordinator: ScreenCaptureDelegate {
    nonisolated func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage, contentRect: CGRect) {
        Task { @MainActor in
            processFrame(image, contentRect: contentRect)
        }
    }

    nonisolated func screenCaptureService(_ service: ScreenCaptureService, didStopUnexpectedly reason: CaptureStopReason) {
        Task { @MainActor in
            await handleUnexpectedStop(reason)
        }
    }
}

// MARK: - SCWindow import
import ScreenCaptureKit
