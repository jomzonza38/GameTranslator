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
    private var pendingFrame: CapturedFrame?
    private var isProcessing = false
    /// The running drain loop, cancelled by stop()
    private var pipelineTask: Task<Void, Never>?
    /// The latest captured frame, re-run when work is waiting on a static screen
    /// (ScreenCaptureKit sends no frames while the window doesn't change)
    private var lastFrame: CapturedFrame?
    /// Skips OCR for frames whose pixels were processed recently (T-0016)
    private var frameFilter = FrameChangeFilter()
    /// Pictures of the original texts on screen, by source text (panel, full-screen
    /// mode). Made once when a text is first shown translated, dropped when it leaves.
    private var sourceThumbnails: [String: CGImage] = [:]
    /// Last logged window frame (T-0020 diagnostics: one log line per change)
    private var lastLoggedWindowFrame: CGRect?
    /// On-screen text is waiting to become stable, which needs another run of the
    /// same pixels — so identical frames must not be skipped until it is translated
    private var isWaitingForStableText = false
    /// A scheduled pipeline run on `lastFrame` (see StaticScreenRerun)
    private var rerunTask: Task<Void, Never>?
    /// Moved on by every start and teardown, so a start that finishes after the user
    /// stopped (or started again) leaves the current state alone
    private var sessions = StartGeneration()
    private let settings = AppSettings.shared
    /// Frame statistics logged every 10 s while translating the capture card picture
    /// (T-0028: how often the exact fingerprint changes on a static Switch screen)
    private var frameStats: FrameStats?

    // Capture card mode (T-0034): OCR only when the text area really changed
    /// Translating the capture card picture (started with `maxCaptureSize`)
    private var isCaptureCardMode = false
    /// Which areas (whole picture / each region) changed beyond capture noise
    private var lumaDetector = LumaChangeDetector()
    /// Slows OCR while it keeps reading the same text
    private var ocrPacer = OCRPacer()
    /// Last OCR result per region, reused for regions whose pixels didn't change
    private var lastRegionOCR: [UUID: OCRFrame] = [:]
    /// Window frame the luma baselines were recorded at (a move/resize re-reads all)
    private var lumaWindowFrame: CGRect?
    /// A change held back by the pacer is scheduled as a re-run; a finishing run
    /// must not cancel it
    private var hasPacedRerun = false

    /// Callback when capture regions change (add/remove/clear)
    var onRegionsChanged: (() -> Void)?

    /// Callback after capture ended on its own (game window closed) and the
    /// session was torn down, so the menu and status icon can refresh
    var onStoppedUnexpectedly: (() -> Void)?

    /// Recent lines and glossary sent to LLM providers
    private let contextBuilder = TranslationContextBuilder()

    /// Provider + source language the on-screen translations came from (nil = not
    /// known yet). When it changes, visible text is translated again.
    private var translationScope: String?

    /// Set when the provider refused the API key or the quota is used up: no
    /// translation requests until the key or provider changes (updateProvider) or a
    /// new session starts. Capture and overlay keep running.
    private var isTranslationPaused = false

    /// Moved on by every updateProvider() (provider picked, key saved, start). A
    /// request remembers the value it was sent with, so a refusal of an old key or
    /// provider can be told apart from one of the current key.
    private var providerGeneration = 0

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

        // Game language or glossary edited while running: on-screen text must be
        // translated again even if the game window doesn't change
        settings.$sourceLanguage
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleRerun(after: Self.rerunSoon) }
            }
            .store(in: &cancellables)
        // Thumbnails switched on/off: redraw the panel even on a static screen
        settings.$showSourceThumbnails
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleRerun(after: Self.rerunSoon) }
            }
            .store(in: &cancellables)
        settings.$gameProfiles
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.scheduleRerun(after: Self.rerunSoon) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Control

    /// Start translating a window. `profileID` names the game profile (title,
    /// glossary); by default it is the window's app name. The capture card picture
    /// (T-0028) passes the card's name — the app can't tell which Switch game runs.
    /// `maxCaptureSize` (pixels) = capture card mode (T-0034): the capture never goes
    /// above the picture's resolution and OCR runs only when the text area changed.
    func start(window: Any, profileID: String? = nil, maxCaptureSize: CGSize? = nil) async throws {
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
        settings.selectGame(id: profileID ?? scWindow.owningApplication?.applicationName ?? scWindow.title ?? "Unknown")
        frameStats = profileID == nil ? nil : FrameStats()
        isCaptureCardMode = maxCaptureSize != nil
        resetCaptureCardChangeState()
        contextBuilder.reset(glossary: settings.currentProfile.glossary)

        let session = sessions.begin()
        selectedWindow = window
        isRunning = true
        status = .capturing
        lastError = nil
        stats = PipelineStats()
        globalState.reset()
        regionStates.removeAll()
        translationScope = nil
        isTranslationPaused = false

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
                frameRate: settings.captureFrameRate,
                maxOutputSize: maxCaptureSize,
                computesLumaGrid: isCaptureCardMode
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
        rerunTask?.cancel()
        rerunTask = nil
        lastFrame = nil
        frameFilter.reset()
        resetCaptureCardChangeState()
        isWaitingForStableText = false
        lastLoggedWindowFrame = nil
        sourceThumbnails.removeAll()

        await screenCapture.stopCapture()
        overlayController.hide()
        panelController.hide()

        status = .idle
        currentRegions = []
        selectedWindow = nil
    }

    /// Called when the provider or its API key changes (and at start)
    func updateProvider() {
        translationService.switchProvider(to: settings.selectedProvider)
        providerGeneration += 1

        // A new key or provider is the user's fix for a refused key / used-up quota
        if isTranslationPaused {
            isTranslationPaused = false
            lastError = nil
            for state in regionStates.values {
                state.failedAt.removeAll()
            }
            globalState.failedAt.removeAll()
            GameLog.log("▶︎ Translation resumed (\(translationService.currentProviderName))")
        }

        // New key or provider: translate what is on screen now, even if it is static
        scheduleRerun(after: Self.rerunSoon)
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
        // Thumbnails are only made in Panel mode — make them for what is on screen now
        scheduleRerun(after: Self.rerunSoon)
    }

    // MARK: - Multi-Region Management

    /// Show the region selector and add a new capture region
    func addCaptureRegion(name: String, color: RegionColor) {
        guard let window = selectedWindow as? SCWindow else { return }
        let windowFrame = screenCapture.currentWindowFrame ?? window.frame

        // Temporarily hide overlay so it doesn't interfere with region selection
        overlayController.hideTemporarily()

        regionSelector.show(over: windowFrame, color: color, onCancel: { [weak self] in
            // Esc — no region added; bring the hidden overlay back
            self?.showOverlayAfterRegionSelection(over: windowFrame)
        }) { [weak self] normalizedRect in
            guard let self = self else { return }
            Task { @MainActor in
                let region = CaptureRegion(name: name, rect: normalizedRect, color: color)
                self.settings.addRegion(region)
                self.regionStates[region.id] = RegionPipelineState()

                GameLog.log("Region added: \(name) (\(color.rawValue)) x=\(String(format: "%.2f", normalizedRect.origin.x)) y=\(String(format: "%.2f", normalizedRect.origin.y)) w=\(String(format: "%.2f", normalizedRect.width)) h=\(String(format: "%.2f", normalizedRect.height))")

                self.showOverlayAfterRegionSelection(over: windowFrame)

                self.onRegionsChanged?()
            }
        }
    }

    /// Re-show the overlay hidden for region selection — only while running in
    /// Overlay mode (not after a stop, and Panel mode has no overlay)
    private func showOverlayAfterRegionSelection(over windowFrame: CGRect) {
        if settings.displayMode == .overlay, isRunning {
            overlayController.show(over: windowFrame)
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

    /// A frame from ScreenCaptureKit (image nil = same pixels as the previous one).
    /// Frames whose pixels were processed recently — a static screen, or a caret /
    /// "next" arrow blinking between a few states — give the same OCR result and are
    /// skipped, unless the window moved or text is waiting to become stable.
    private func handleCapturedFrame(image: CGImage?, fingerprint: UInt64, startFrame: CGRect, capturedWindowSize: CGSize?, lumaGrid: LumaGrid?) {
        guard isRunning else { return }
        if var stats = frameStats {
            if let line = stats.record(changed: image != nil, now: CFAbsoluteTimeGetCurrent()) {
                GameLog.log("Capture card frames: \(line)")
            }
            frameStats = stats
        }
        let frame: CapturedFrame
        if let image {
            frame = CapturedFrame(image: image, startFrame: startFrame, fingerprint: fingerprint,
                                  capturedWindowSize: capturedWindowSize, lumaGrid: lumaGrid)
            lastFrame = frame
        } else if let last = lastFrame, last.fingerprint == fingerprint {
            frame = last
        } else {
            return // unchanged frame whose image we don't have (arrived out of order)
        }

        let windowFrame = screenCapture.currentWindowFrame
        followWindowSize(windowFrame, capturedWindowSize: frame.capturedWindowSize)

        if isCaptureCardMode, let grid = frame.lumaGrid {
            handleCaptureCardFrame(frame, grid: grid, windowFrame: windowFrame)
            return
        }

        guard frameFilter.shouldProcess(
            frame.fingerprint,
            windowFrame: windowFrame,
            workWaiting: isWaitingForStableText
        ) else { return }
        frameStats?.processed += 1
        processFrame(frame)
    }

    /// Capture card mode (T-0034): OCR only the areas (whole picture, or each enabled
    /// region) whose brightness grid moved beyond capture noise, and at most once a
    /// second while OCR keeps reading the same text. A move/resize or text waiting to
    /// become stable reads everything, as before.
    private func handleCaptureCardFrame(_ frame: CapturedFrame, grid: LumaGrid, windowFrame: CGRect?) {
        let mustReadAll = isWaitingForStableText || windowFrame != lumaWindowFrame
        let areas = lumaAreas(for: frame, windowFrame: windowFrame)
        let changed = mustReadAll ? Set(areas.map(\.0)) : lumaDetector.changedAreas(grid, areas: areas)
        guard !changed.isEmpty else { return }

        if !mustReadAll {
            let wait = ocrPacer.delayBeforeNextRun(now: CFAbsoluteTimeGetCurrent())
            if wait > 0 {
                // Read it when the pacer allows, even if no new frame arrives
                lastFrame = frame
                scheduleRerun(after: wait)
                hasPacedRerun = true
                return
            }
        }

        var work = frame
        if !mustReadAll {
            let regionIDs = changed.compactMap { area -> UUID? in
                if case .region(let id) = area { return id }
                return nil
            }
            work.onlyRegions = changed.contains(.whole) ? nil : Set(regionIDs)
        }
        frameStats?.processed += 1
        processFrame(work)
    }

    /// The areas watched for change: each enabled region (rect in the captured image),
    /// or the whole picture without regions
    private func lumaAreas(for frame: CapturedFrame, windowFrame: CGRect?) -> [(LumaChangeDetector.Area, CGRect?)] {
        let regions = settings.captureRegions.filter(\.isEnabled)
        guard !settings.captureRegions.isEmpty else { return [(.whole, nil)] }
        let visibleFrame = windowFrame ?? frame.startFrame
        let mapping = CaptureGeometry.mappingFrame(cgBounds: visibleFrame, capturedSize: frame.capturedWindowSize)
        return regions.map { region in
            (.region(region.id), CaptureGeometry.convertNormalized(region.rect, from: visibleFrame, to: mapping))
        }
    }

    private func resetCaptureCardChangeState() {
        lumaDetector.reset()
        ocrPacer.reset()
        lastRegionOCR.removeAll()
        lumaWindowFrame = nil
        hasPacedRerun = false
    }

    /// Keep the capture sized to the captured window (resize / full-screen switch while
    /// translating) and log the window frame and the frame used for mapping whenever
    /// they change (T-0020)
    private func followWindowSize(_ windowFrame: CGRect?, capturedWindowSize: CGSize?) {
        if let windowFrame {
            let mapping = CaptureGeometry.mappingFrame(cgBounds: windowFrame, capturedSize: capturedWindowSize)
            let key = CGRect(x: windowFrame.minX, y: windowFrame.minY, width: windowFrame.width, height: mapping.height)
            if key != lastLoggedWindowFrame {
                lastLoggedWindowFrame = key
                GameLog.log("Window frame (CGWindowList): \(ScreenCaptureService.describe(windowFrame)) → mapping frame (captured window): \(ScreenCaptureService.describe(mapping))")
            }
        }
        screenCapture.requestResize(capturedWindowSize: capturedWindowSize, cgWindowSize: windowFrame?.size)
    }

    /// Run the pipeline on `frame` (or queue it behind the run in progress). Re-runs
    /// on the last frame (StaticScreenRerun) call this directly, bypassing the filter.
    private func processFrame(_ frame: CapturedFrame) {
        guard isRunning else { return }
        hasPacedRerun = false
        // Re-runs of the last frame read every region
        var last = frame
        last.onlyRegions = nil
        lastFrame = last
        guard !isProcessing else {
            pendingFrame = frame
            return
        }

        // Claim the pipeline now, not inside the Task: frames already queued on the
        // main actor would otherwise each start their own pipeline before it runs
        isProcessing = true
        pipelineTask = Task { [weak self] in
            await self?.drainPipeline(frame)
        }
    }

    private func drainPipeline(_ first: CapturedFrame) async {
        var next: CapturedFrame? = first

        while let frame = next, !Task.isCancelled {
            frameFilter.recordProcessed(frame.fingerprint, windowFrame: screenCapture.currentWindowFrame)
            if isCaptureCardMode, let grid = frame.lumaGrid {
                let windowFrame = screenCapture.currentWindowFrame
                lumaDetector.record(grid, areas: lumaAreas(for: frame, windowFrame: windowFrame).map(\.0))
                lumaWindowFrame = windowFrame
            }
            await runPipeline(frame)
            next = pendingFrame
            pendingFrame = nil
        }
        isProcessing = false
    }

    /// How long to wait before retrying a text whose translation request failed
    private let retryDelay: CFAbsoluteTime = 3

    /// Delay for a re-run triggered by an event (resume, key, provider, language, glossary)
    private static let rerunSoon: TimeInterval = 0.2

    /// Run the pipeline on the last frame after `delay`, unless a new frame's run
    /// reschedules first. Guarded like a real frame: running session only, and
    /// processFrame queues it behind a run in progress (isProcessing).
    private func scheduleRerun(after delay: TimeInterval) {
        rerunTask?.cancel()
        guard isRunning else { return }
        let session = sessions.current
        rerunTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self,
                  self.sessions.isCurrent(session), self.isRunning,
                  let frame = self.lastFrame else { return }
            self.processFrame(frame)
        }
    }

    /// After a run: re-run on the same frame when work is waiting (text not yet stable,
    /// a retry back-off, a glossary edit settling); otherwise stay idle
    private func planRerun(after works: [RegionFrameWork]) {
        var untranslatedFailedAt: [CFAbsoluteTime?] = []
        for work in works {
            for text in work.currentTexts where work.state.translation(for: text.text) == nil {
                untranslatedFailedAt.append(work.state.failedAt[text.text])
            }
        }
        isWaitingForStableText = !isTranslationPaused && untranslatedFailedAt.contains { $0 == nil }

        let delay = StaticScreenRerun.delay(
            untranslatedFailedAt: untranslatedFailedAt,
            isPaused: isTranslationPaused,
            glossaryAppliesAt: contextBuilder.pendingGlossaryAppliesAt,
            now: CFAbsoluteTimeGetCurrent(),
            retryDelay: retryDelay
        )
        if let delay {
            scheduleRerun(after: delay)
        } else if !hasPacedRerun {
            rerunTask?.cancel()
            rerunTask = nil
        }
    }

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

    private func runPipeline(_ frame: CapturedFrame) async {
        let image = frame.image
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        await applyGlossaryChangesIfNeeded()
        applyTranslationScopeChangeIfNeeded()

        do {
            // Step 1: OCR settings
            // Pick up the latest OCR settings every frame so changes apply while running
            ocrService.minimumConfidence = settings.minimumConfidence
            ocrService.recognitionLevel = settings.effectiveOCRAccuracy == .accurate ? .accurate : .fast
            ocrService.recognitionLanguages = settings.sourceLanguage.visionLanguages
            ocrService.minimumTextLength = settings.sourceLanguage.usesWordSpacing ? 2 : 1

            let imageSize = CGSize(width: image.width, height: image.height)
            // The visible window (CGWindowList) and the window ScreenCaptureKit captured —
            // the image covers the latter, which can reach above the screen (T-0020)
            let visibleFrame = screenCapture.currentWindowFrame ?? frame.startFrame
            let windowFrame = CaptureGeometry.mappingFrame(cgBounds: visibleFrame, capturedSize: frame.capturedWindowSize)
            let captureRegions = settings.captureRegions
            let ocrStart = CFAbsoluteTimeGetCurrent()
            var textsDetected = 0

            // Vision may still be preparing its model (first use): say so, since this
            // first OCR can take about a minute
            let isFirstOCR = !OCRService.isVisionReady
            if isFirstOCR {
                status = .preparingOCR
                panelController.setPreparingOCR(true)
            }
            defer {
                if isFirstOCR {
                    panelController.setPreparingOCR(false)
                    if status == .preparingOCR { status = .running }
                }
            }

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
                    // Regions are drawn over the visible window; the image is the captured one
                    let regionInImage = CaptureGeometry.convertNormalized(captureRegion.rect, from: visibleFrame, to: windowFrame)
                    let ocrFrame: OCRFrame
                    if let only = frame.onlyRegions, !only.contains(captureRegion.id),
                       let previous = lastRegionOCR[captureRegion.id] {
                        // Capture card mode: this region's pixels didn't change (T-0034)
                        ocrFrame = previous
                    } else {
                        ocrFrame = try await ocrService.recognizeText(
                            in: image,
                            imageSize: imageSize,
                            cropTo: regionInImage
                        )
                        if isCaptureCardMode { lastRegionOCR[captureRegion.id] = ocrFrame }
                    }
                    textsDetected += ocrFrame.texts.count

                    works.append(prepareRegion(
                        ocrFrame: ocrFrame, filterRegion: regionInImage,
                        regionColor: captureRegion.color, regionName: captureRegion.name,
                        regionID: captureRegion.id, state: state,
                        ocrTime: CFAbsoluteTimeGetCurrent() - regionOCRStart
                    ))
                }
            }
            let ocrTime = CFAbsoluteTimeGetCurrent() - ocrStart
            guard isRunning, !Task.isCancelled else { return }
            if isCaptureCardMode {
                let signature = works.map { $0.currentTexts.map(\.text).joined(separator: "\n") }.joined(separator: "\u{1}")
                let wasSlowed = ocrPacer.isSlowed
                ocrPacer.recordRun(signature: signature, at: CFAbsoluteTimeGetCurrent())
                if ocrPacer.isSlowed != wasSlowed {
                    GameLog.log(ocrPacer.isSlowed ? "Capture card: same text read again — OCR at most once a second"
                                                  : "Capture card: text changed — OCR at full rate")
                }
            }

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
            // Text in the part of the captured window above the screen (full-screen
            // title-bar area) can't be shown or outlined
            allTranslatedRegions = allTranslatedRegions.filter {
                CaptureGeometry.isVisible($0.sourceRect, within: visibleFrame)
            }

            // Step 5: Resolve overlapping regions — push colliding boxes down
            let resolvedRegions = attachSourceThumbnails(
                to: RegionLayout.resolveOverlaps(allTranslatedRegions, options: layoutOptions),
                works: works,
                image: image
            )

            // Step 6: ALWAYS update display (overlay or panel)
            currentRegions = resolvedRegions
            if settings.displayMode == .overlay {
                overlayController.updateRegions(resolvedRegions, windowFrame: windowFrame)
            } else {
                panelController.updateRegions(resolvedRegions)
            }

            planRerun(after: works)

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

        // Paused after a refused key / used-up quota: no request until the user fixes it
        guard !isTranslationPaused else { return }

        // The provider/key this request goes to — the key may change while it is in flight
        let requestGeneration = providerGeneration
        let requestProvider = translationService.currentProviderName
        let requestUsesApiKey = translationService.currentProviderUsesApiKey

        let labels = works.filter { !$0.textsToTranslate.isEmpty }.map { $0.regionName ?? "full-screen" }
        GameLog.log("Translating \(texts.count) texts via \(requestProvider) [\(labels.joined(separator: ", "))]...")

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
            let now = CFAbsoluteTimeGetCurrent()
            for text in texts {
                guard let translation = translations[text] else {
                    // No real translation (the LLM answered with chatter): not cached —
                    // retry after the normal back-off instead of every frame
                    for work in works where work.textsToTranslate.contains(text) {
                        work.state.failedAt[text] = now
                    }
                    GameLog.log("\u{2717} No translation for \"\(text)\" — will retry")
                    continue
                }
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
                // Learning window (T-0022): in-memory update; words and saving run later, off the main actor
                LearningStore.shared.add(
                    original: text,
                    translation: translation,
                    game: settings.currentProfile.title,
                    languageCode: settings.sourceLanguage.rawValue
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

            switch TranslationRefusal.outcome(
                for: error,
                provider: requestProvider,
                usesApiKey: requestUsesApiKey,
                requestGeneration: requestGeneration,
                currentGeneration: providerGeneration
            ) {
            case .pause(let message):
                // Key refused / quota used up: retrying every few seconds can't help
                isTranslationPaused = true
                lastError = message
                GameLog.log("⏸ Translation paused until the API key or provider changes")
            case .ignoreOutdated:
                // Sent before the key/provider changed — the new one hasn't failed
                GameLog.log("Refusal was for the previous key/provider (\(requestProvider)) — not pausing")
            case .notARefusal:
                lastError = error.localizedDescription
            }
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

    // MARK: - Source thumbnails (T-0018)

    /// Panel + full-screen mode: give each translated text a picture of its original
    /// pixels. A picture is cut only the first time a text is shown translated —
    /// unchanged texts reuse theirs, so a static screen costs nothing extra.
    private func attachSourceThumbnails(
        to regions: [TranslatedRegion],
        works: [RegionFrameWork],
        image: CGImage
    ) -> [TranslatedRegion] {
        guard settings.displayMode == .panel,
              settings.showSourceThumbnails,
              settings.captureRegions.isEmpty,
              let work = works.first(where: { $0.regionID == nil }) else {
            sourceThumbnails.removeAll()
            return regions
        }

        let onScreen = Set(work.currentTexts.map(\.text))
        sourceThumbnails = sourceThumbnails.filter { onScreen.contains($0.key) }

        for detected in work.currentTexts
        where sourceThumbnails[detected.text] == nil && work.state.translation(for: detected.text) != nil {
            sourceThumbnails[detected.text] = SourceThumbnail.make(from: image, box: detected.boundingBox)
        }

        return regions.map { region in
            region.regionID == nil ? region.withSourceThumbnail(sourceThumbnails[region.originalText]) : region
        }
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

    /// Provider or source language changed (Settings, while running): drop the
    /// on-screen translations so visible text is translated again by the new one.
    /// The service cache is keyed by provider + language, so it needs no clearing.
    private func applyTranslationScopeChangeIfNeeded() {
        let scope = translationService.translationScope
        defer { translationScope = scope }
        guard let previous = translationScope, previous != scope else { return }

        globalState.reset()
        for state in regionStates.values {
            state.reset()
        }
        contextBuilder.clearRecentLines()
        GameLog.log("Translation provider/language changed (\(scope)) — re-translating on-screen text")
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

// MARK: - Frame skipping

/// A captured frame and the fingerprint of its pixels
struct CapturedFrame {
    let image: CGImage
    /// The window's frame when capture started (fallback if CGWindowList has none)
    let startFrame: CGRect
    let fingerprint: UInt64
    /// Size (points) of the window ScreenCaptureKit captured; nil if unknown (T-0020)
    let capturedWindowSize: CGSize?
    /// Brightness grid of the picture (capture card mode, T-0034)
    var lumaGrid: LumaGrid? = nil
    /// Capture card mode: OCR only these regions, reuse the last result for the
    /// others (nil = all)
    var onlyRegions: Set<UUID>? = nil
}

/// Remembers the fingerprints of recently processed frames. A frame with the same
/// pixels at the same window position gives the same OCR result, so it can be skipped.
/// Keeping several (not just the last) also covers things that blink between a few
/// states — a text caret, a "▼ next" arrow.
struct FrameChangeFilter {
    let capacity: Int
    private(set) var recent: [UInt64] = []
    private var lastWindowFrame: CGRect?

    init(capacity: Int = 8) {
        self.capacity = capacity
    }

    /// Whether the frame must go through the pipeline
    func shouldProcess(_ fingerprint: UInt64, windowFrame: CGRect?, workWaiting: Bool) -> Bool {
        // Text waiting to become stable needs a second run of the same pixels;
        // a moved window needs its overlay repositioned
        workWaiting || windowFrame != lastWindowFrame || !recent.contains(fingerprint)
    }

    /// The frame is being run through the pipeline
    mutating func recordProcessed(_ fingerprint: UInt64, windowFrame: CGRect?) {
        recent.removeAll { $0 == fingerprint }
        recent.append(fingerprint)
        if recent.count > capacity {
            recent.removeFirst(recent.count - capacity)
        }
        lastWindowFrame = windowFrame
    }

    mutating func reset() {
        recent.removeAll()
        lastWindowFrame = nil
    }
}

/// Counts frames over an interval (T-0028 diagnostics): all frames ScreenCaptureKit
/// delivered, those whose pixels changed (exact fingerprint), and those that went on
/// to OCR. One log line per interval.
struct FrameStats {
    var interval: CFAbsoluteTime = 10
    private(set) var received = 0
    private(set) var changed = 0
    var processed = 0
    private var startedAt: CFAbsoluteTime?

    /// Record one frame; returns the log line when an interval has passed
    mutating func record(changed isChanged: Bool, now: CFAbsoluteTime) -> String? {
        let start = startedAt ?? now
        startedAt = start
        received += 1
        if isChanged { changed += 1 }
        guard now - start >= interval else { return nil }
        let line = "\(received) received, \(changed) with changed pixels, \(processed) sent to OCR in \(Int((now - start).rounded())) s"
        received = 0
        changed = 0
        processed = 0
        startedAt = now
        return line
    }
}

// MARK: - Static screen re-run

/// When to run the pipeline again on the last captured frame. ScreenCaptureKit sends
/// no frames while the game window doesn't change (e.g. a dialog waiting for a click),
/// so waiting work would otherwise wait forever.
enum StaticScreenRerun {
    /// Delay until the next re-run, or nil to stay idle.
    /// - Parameters:
    ///   - untranslatedFailedAt: one entry per on-screen text without a translation —
    ///     when its last request failed, or nil if it is waiting to become stable
    ///   - isPaused: requests are paused (refused key): untranslated text can't progress
    ///   - glossaryAppliesAt: when a glossary edit settles, if one is pending
    static func delay(
        untranslatedFailedAt: [CFAbsoluteTime?],
        isPaused: Bool,
        glossaryAppliesAt: CFAbsoluteTime?,
        now: CFAbsoluteTime,
        retryDelay: CFAbsoluteTime,
        stabilityRecheck: TimeInterval = 0.5
    ) -> TimeInterval? {
        var waits: [TimeInterval] = []
        if let glossaryAppliesAt {
            waits.append(glossaryAppliesAt - now)
        }
        if !isPaused {
            for failedAt in untranslatedFailedAt {
                // Back-off ends at failedAt + retryDelay; unstable text is checked again soon
                waits.append(failedAt.map { $0 + retryDelay - now } ?? stabilityRecheck)
            }
        }
        guard let soonest = waits.min() else { return nil }
        return max(soonest, minimumDelay)
    }

    /// Never re-run more often than this
    static let minimumDelay: TimeInterval = 0.1
}

// MARK: - ScreenCaptureDelegate

extension PipelineCoordinator: ScreenCaptureDelegate {
    nonisolated func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage?, fingerprint: UInt64, contentRect: CGRect, capturedWindowSize: CGSize?, lumaGrid: LumaGrid?) {
        Task { @MainActor in
            handleCapturedFrame(image: image, fingerprint: fingerprint, startFrame: contentRect,
                                capturedWindowSize: capturedWindowSize, lumaGrid: lumaGrid)
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
