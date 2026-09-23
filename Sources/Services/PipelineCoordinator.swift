import Foundation
import CoreGraphics
import AppKit

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
    /// Continuous translation paused (frames are ignored unless a single shot is requested)
    @Published private(set) var isPaused = false
    /// Translations hidden from screen (pipeline keeps running)
    @Published private(set) var isDisplayHidden = false

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
    private var singleShotRequested = false
    private let settings = AppSettings.shared

    /// Callback when capture regions change (add/remove/clear)
    var onRegionsChanged: (() -> Void)?

    /// Recent lines and glossary sent to LLM providers
    private let contextBuilder = TranslationContextBuilder()

    // MARK: - Init

    init() {
        self.translationService = TranslationService()
        self.overlayController = OverlayWindowController()
        self.panelController = TranslationPanelController()

        screenCapture.delegate = self
        ocrService.minimumConfidence = settings.minimumConfidence
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

        selectedWindow = window
        isPaused = false
        isDisplayHidden = false
        singleShotRequested = false
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

        // Start screen capture
        try await screenCapture.startCapture(
            window: scWindow,
            frameRate: settings.captureFrameRate
        )

        GameLog.log("✓ Capture started successfully")
        status = .running
    }

    func stop() async {
        guard isRunning else { return }

        await screenCapture.stopCapture()
        overlayController.hide()
        panelController.hide()

        isRunning = false
        isPaused = false
        isDisplayHidden = false
        singleShotRequested = false
        status = .idle
        currentRegions = []
        selectedWindow = nil
    }

    // MARK: - Pause / Single Shot / Visibility

    /// Pause or resume continuous translation
    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
        singleShotRequested = false
        GameLog.log(isPaused ? "Paused" : "Resumed")
    }

    /// Pause continuous translation and translate only the next captured frame
    func translateOnce() {
        guard isRunning else { return }
        isPaused = true
        singleShotRequested = true
        if isDisplayHidden {
            toggleDisplayHidden()
        }
        GameLog.log("Single-shot translation requested")
    }

    /// Hide or show translations on screen without stopping capture
    func toggleDisplayHidden() {
        guard isRunning else { return }
        isDisplayHidden.toggle()
        if settings.displayMode == .overlay {
            if isDisplayHidden {
                overlayController.hideTemporarily()
            } else if let window = selectedWindow as? SCWindow {
                overlayController.show(over: screenCapture.currentWindowFrame ?? window.frame)
            }
        } else {
            panelController.setHidden(isDisplayHidden)
        }
    }

    func updateProvider() {
        translationService.switchProvider(to: settings.selectedProvider)
    }

    /// Switch between overlay and panel display modes while running
    func switchDisplayMode() {
        guard isRunning, let window = selectedWindow as? SCWindow else { return }
        isDisplayHidden = false

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

                // Re-show overlay if in overlay mode (unless the user hid translations)
                if self.settings.displayMode == .overlay, self.isRunning, !self.isDisplayHidden {
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
        if isPaused {
            guard singleShotRequested else { return }
            singleShotRequested = false
        }

        guard !isProcessing else {
            pendingFrame = (image, contentRect)
            return
        }

        Task { [weak self] in
            await self?.drainPipeline(image: image, contentRect: contentRect)
        }
    }

    private func drainPipeline(image: CGImage, contentRect: CGRect) async {
        var next: (image: CGImage, contentRect: CGRect)? = (image, contentRect)

        while let frame = next {
            isProcessing = true
            await runPipeline(image: frame.image, contentRect: frame.contentRect)
            isProcessing = false

            next = pendingFrame
            pendingFrame = nil
        }
    }

    private func runPipeline(image: CGImage, contentRect: CGRect) async {
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        await applyGlossaryChangesIfNeeded()

        do {
            // Step 1: OCR (whole frame — shared across all regions)
            // Pick up the latest OCR settings every frame so changes apply while running
            ocrService.minimumConfidence = settings.minimumConfidence
            ocrService.recognitionLevel = settings.effectiveOCRAccuracy == .accurate ? .accurate : .fast
            ocrService.recognitionLanguages = settings.sourceLanguage.visionLanguages
            ocrService.minimumTextLength = settings.sourceLanguage.usesWordSpacing ? 2 : 1

            let ocrStart = CFAbsoluteTimeGetCurrent()
            let imageSize = CGSize(width: image.width, height: image.height)
            let ocrFrame = try await ocrService.recognizeText(in: image, imageSize: imageSize)
            let ocrTime = CFAbsoluteTimeGetCurrent() - ocrStart

            let windowFrame = screenCapture.currentWindowFrame ?? contentRect
            let captureRegions = settings.captureRegions

            var allTranslatedRegions: [TranslatedRegion] = []
            var totalTranslateTime: Double = 0

            if captureRegions.isEmpty {
                // No regions defined — process full screen with global state
                let (regions, translateTime) = await processRegionPipeline(
                    ocrFrame: ocrFrame,
                    filterRegion: nil,
                    regionColor: nil,
                    regionName: nil,
                    state: globalState,
                    windowFrame: windowFrame,
                    ocrTime: ocrTime
                )
                allTranslatedRegions.append(contentsOf: regions)
                totalTranslateTime += translateTime
            } else {
                // Process each capture region separately
                for captureRegion in captureRegions {
                    // Ensure we have state for this region
                    if regionStates[captureRegion.id] == nil {
                        regionStates[captureRegion.id] = RegionPipelineState()
                    }
                    let state = regionStates[captureRegion.id]!

                    let (regions, translateTime) = await processRegionPipeline(
                        ocrFrame: ocrFrame,
                        filterRegion: captureRegion.rect,
                        regionColor: captureRegion.color,
                        regionName: captureRegion.name,
                        state: state,
                        windowFrame: windowFrame,
                        ocrTime: ocrTime
                    )
                    allTranslatedRegions.append(contentsOf: regions)
                    totalTranslateTime += translateTime
                }
            }

            // Step 6: Resolve overlapping regions — push colliding boxes down
            let resolvedRegions = RegionLayout.resolveOverlaps(allTranslatedRegions, options: layoutOptions)

            // Step 7: ALWAYS update display (overlay or panel)
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
                translateTime: totalTranslateTime,
                totalTime: totalTime,
                textsDetected: ocrFrame.texts.count,
                textsTranslated: allTranslatedRegions.count
            )
        } catch {
            GameLog.log("✗ Pipeline error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    /// Process the pipeline for a single region (or full-screen when filterRegion is nil).
    /// Returns translated regions and the time spent translating.
    private func processRegionPipeline(
        ocrFrame: OCRFrame,
        filterRegion: CGRect?,
        regionColor: RegionColor?,
        regionName: String?,
        state: RegionPipelineState,
        windowFrame: CGRect,
        ocrTime: Double
    ) async -> ([TranslatedRegion], Double) {
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

        // Translate new/changed/untranslated texts
        var translateTime: Double = 0
        do {
            let translateStart = CFAbsoluteTimeGetCurrent()

            // Promote stale cache hits back to active cache
            for text in diffResult.unchangedTexts {
                if state.cachedTranslations[text.text] == nil,
                   let stale = state.staleTranslations.removeValue(forKey: text.text) {
                    state.cachedTranslations[text.text] = stale.translation
                }
            }
            for text in diffResult.newTexts {
                if let stale = state.staleTranslations.removeValue(forKey: text.text) {
                    state.cachedTranslations[text.text] = stale.translation
                }
            }

            // Collect texts that need translation
            var textsToTranslate = diffResult.textsNeedingTranslation.filter {
                state.cachedTranslations[$0.text] == nil
            }

            // Retry any "unchanged" texts still missing a translation
            let untranslated = diffResult.unchangedTexts.filter {
                state.cachedTranslations[$0.text] == nil
            }
            if !untranslated.isEmpty {
                textsToTranslate.append(contentsOf: untranslated)
                let label = regionName ?? "full-screen"
                GameLog.log("Retrying \(untranslated.count) previously untranslated texts [\(label)]")
            }

            // Texts that are exactly a glossary term use the fixed translation — no API call
            textsToTranslate = textsToTranslate.filter { detected in
                guard let fixed = contextBuilder.fixedTranslation(for: detected.text) else {
                    return true
                }
                state.cachedTranslations[detected.text] = fixed
                return false
            }

            if !textsToTranslate.isEmpty {
                let textStrings = textsToTranslate.map(\.text)
                let label = regionName ?? "full-screen"
                GameLog.log("Translating \(textStrings.count) texts via \(translationService.currentProviderName) [\(label)]...")

                let translations = try await translationService.translateBatch(
                    textStrings,
                    context: contextBuilder.context(
                        for: textStrings,
                        sourceLanguageName: settings.sourceLanguage.englishName,
                        gameTitle: settings.currentProfile.title,
                        includeRecentLines: settings.useConversationContext
                    )
                )

                // Iterate in on-screen order so the context reads naturally
                for text in textStrings {
                    guard let translation = translations[text] else { continue }
                    state.cachedTranslations[text] = translation
                    contextBuilder.remember(original: text, translation: translation)
                    TranslationHistory.shared.add(
                        original: text,
                        translation: translation,
                        game: settings.currentProfile.title
                    )
                    GameLog.log("\u{2713} \"\(text)\" \u{2192} \"\(translation)\"")
                }
            }

            // Move removed translations to stale cache (10s grace period)
            if diffResult.hasChanges {
                let now = CFAbsoluteTimeGetCurrent()
                for removed in diffResult.removedTexts {
                    if let translation = state.cachedTranslations.removeValue(forKey: removed.text) {
                        state.staleTranslations[removed.text] = (translation, now + 10)
                    }
                }
                state.staleTranslations = state.staleTranslations.filter { $0.value.expiry > now }
            }

            translateTime = CFAbsoluteTimeGetCurrent() - translateStart
        } catch {
            GameLog.log("\u{2717} Translation error: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }

        // Build regions from current OCR data + cached translations
        let allCurrentTexts = diffResult.unchangedTexts +
            diffResult.newTexts +
            diffResult.changedTexts.map(\.new)

        let regions = RegionLayout.buildRegions(
            from: allCurrentTexts,
            windowFrame: windowFrame,
            options: layoutOptions,
            regionColor: regionColor,
            regionName: regionName,
            translation: state.translation(for:)
        )

        return (regions, translateTime)
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

    nonisolated func screenCaptureService(_ service: ScreenCaptureService, didEncounterError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}

// MARK: - SCWindow import
import ScreenCaptureKit
