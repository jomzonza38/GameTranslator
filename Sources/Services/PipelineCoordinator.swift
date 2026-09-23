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

    // MARK: - Services

    private let screenCapture = ScreenCaptureService()
    private let ocrService = OCRService()
    private let translationService: TranslationService
    private let overlayController: OverlayWindowController
    private let panelController: TranslationPanelController
    private let regionSelector = RegionSelectorWindow()

    // MARK: - Per-Region Pipeline State

    /// Holds the pipeline state (text tracker, caches) for each capture region.
    /// When no regions are defined, a single "global" state is used.
    private class RegionPipelineState {
        let textTracker = TextTracker()
        var cachedTranslations: [String: String] = [:]
        var staleTranslations: [String: (translation: String, expiry: CFAbsoluteTime)] = [:]
        var lastLoggedTextCount = -1

        func reset() {
            textTracker.reset()
            cachedTranslations.removeAll()
            staleTranslations.removeAll()
            lastLoggedTextCount = -1
        }
    }

    /// Pipeline state for full-screen mode (no regions defined)
    private let globalState = RegionPipelineState()

    /// Pipeline state per capture region, keyed by region UUID
    private var regionStates: [UUID: RegionPipelineState] = [:]

    // MARK: - State

    private var selectedWindow: Any? // SCWindow
    private var pendingFrame: (image: CGImage, contentRect: CGRect)?
    private var isProcessing = false
    private let settings = AppSettings.shared

    /// Callback when capture regions change (add/remove/clear)
    var onRegionsChanged: (() -> Void)?

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
            let resolvedRegions = resolveOverlaps(allTranslatedRegions)

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
        let mergedFrame = Self.mergeAdjacentLines(
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

            if !textsToTranslate.isEmpty {
                let textStrings = textsToTranslate.map(\.text)
                let label = regionName ?? "full-screen"
                GameLog.log("Translating \(textStrings.count) texts via \(translationService.currentProviderName) [\(label)]...")

                let translations = try await translationService.translateBatch(textStrings)

                for (text, translation) in translations {
                    state.cachedTranslations[text] = translation
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

        let regions = buildRegions(
            from: allCurrentTexts,
            windowFrame: windowFrame,
            state: state,
            regionColor: regionColor,
            regionName: regionName
        )

        return (regions, translateTime)
    }

    // MARK: - Region Building

    /// Convert detected texts + cached translations into overlay regions
    private func buildRegions(
        from texts: [DetectedText],
        windowFrame: CGRect,
        state: RegionPipelineState,
        regionColor: RegionColor?,
        regionName: String?
    ) -> [TranslatedRegion] {
        texts.compactMap { detected -> TranslatedRegion? in
            guard let translation = state.cachedTranslations[detected.text] ?? state.staleTranslations[detected.text]?.translation else { return nil }

            // Convert normalized bounding box to screen coordinates
            let screenRect = CGRect(
                x: windowFrame.origin.x + detected.boundingBox.origin.x * windowFrame.width,
                y: windowFrame.origin.y + detected.boundingBox.origin.y * windowFrame.height,
                width: detected.boundingBox.width * windowFrame.width,
                height: detected.boundingBox.height * windowFrame.height
            )

            var fontSize = settings.autoFontSize
                ? OCRService.estimateFontSize(
                    boundingBoxHeight: detected.boundingBox.height,
                    windowHeight: windowFrame.height
                )
                : settings.overlayFontSize

            // Auto-shrink font so Thai translation fits within ~1.5x the original
            let displayText = settings.showOriginalText
                ? "\(translation)\n(\(detected.text))"
                : translation
            let maxHeight = screenRect.height * 1.5
            let minFontSize: CGFloat = 8

            while fontSize > minFontSize {
                let estimatedHeight = Self.estimateTextHeight(
                    displayText,
                    width: screenRect.width,
                    fontSize: fontSize
                )
                if estimatedHeight <= maxHeight {
                    break
                }
                fontSize -= 1
            }

            return TranslatedRegion(
                originalText: detected.text,
                translatedText: translation,
                screenRect: screenRect,
                fontSize: fontSize,
                regionColor: regionColor,
                regionName: regionName
            )
        }
    }

    // MARK: - Overlap Resolution

    private func resolveOverlaps(_ regions: [TranslatedRegion]) -> [TranslatedRegion] {
        guard regions.count > 1 else {
            return regions.map { adjustHeight(for: $0) }
        }

        var placed = regions.map { adjustHeight(for: $0) }
        placed.sort { $0.screenRect.minY < $1.screenRect.minY }

        let gap: CGFloat = 4
        for i in 1..<placed.count {
            for j in 0..<i {
                let a = placed[j].screenRect
                let b = placed[i].screenRect

                let xOverlap = a.minX < b.maxX && b.minX < a.maxX
                let yOverlap = a.minY < b.maxY && b.minY < a.maxY

                if xOverlap && yOverlap {
                    let newY = a.maxY + gap
                    let newRect = CGRect(
                        x: b.origin.x,
                        y: newY,
                        width: b.width,
                        height: b.height
                    )
                    placed[i] = placed[i].withScreenRect(newRect)
                }
            }
        }

        return placed
    }

    private func adjustHeight(for region: TranslatedRegion) -> TranslatedRegion {
        let displayText = settings.showOriginalText
            ? "\(region.translatedText)\n(\(region.originalText))"
            : region.translatedText

        let estimatedHeight = Self.estimateTextHeight(
            displayText,
            width: region.screenRect.width,
            fontSize: region.fontSize
        )

        guard estimatedHeight > region.screenRect.height else { return region }

        let cappedHeight = min(estimatedHeight, region.screenRect.height * 1.5)

        let newRect = CGRect(
            x: region.screenRect.origin.x,
            y: region.screenRect.origin.y,
            width: region.screenRect.width,
            height: cappedHeight
        )
        return region.withScreenRect(newRect)
    }

    private static func estimateTextHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 40), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )
        return ceil(rect.height) + 8
    }

    // MARK: - Line Merging

    private static func mergeAdjacentLines(_ frame: OCRFrame, separator: String = " ") -> OCRFrame {
        guard frame.texts.count > 1 else { return frame }

        let lines = frame.texts.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        var merged: [DetectedText] = []
        var i = 0

        while i < lines.count {
            var current = lines[i]
            i += 1

            while i < lines.count {
                let next = lines[i]
                let currentBox = current.boundingBox
                let nextBox = next.boundingBox

                let gap = nextBox.minY - currentBox.maxY
                let lineHeight = currentBox.height

                let gapOK = gap >= -0.01 && gap < lineHeight * 1.5

                let overlapLeft = max(currentBox.minX, nextBox.minX)
                let overlapRight = min(currentBox.maxX, nextBox.maxX)
                let overlapWidth = max(0, overlapRight - overlapLeft)
                let minWidth = min(currentBox.width, nextBox.width)
                let horizontalOK = minWidth > 0 && (overlapWidth / minWidth) > 0.3

                guard gapOK && horizontalOK else { break }

                let mergedText = current.text + separator + next.text
                let mergedBox = CGRect(
                    x: min(currentBox.minX, nextBox.minX),
                    y: min(currentBox.minY, nextBox.minY),
                    width: max(currentBox.maxX, nextBox.maxX) - min(currentBox.minX, nextBox.minX),
                    height: nextBox.maxY - currentBox.minY
                )
                let mergedConfidence = min(current.confidence, next.confidence)

                current = DetectedText(
                    text: mergedText,
                    boundingBox: mergedBox,
                    confidence: mergedConfidence
                )
                i += 1
            }

            merged.append(current)
        }

        return OCRFrame(texts: merged, imageSize: frame.imageSize)
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

// MARK: - Supporting Types

enum PipelineStatus: String {
    case idle = "Idle"
    case capturing = "Capturing..."
    case running = "Running"
    case error = "Error"

    var displayName: String {
        switch self {
        case .idle: return "พร้อมใช้งาน"
        case .capturing: return "กำลังจับภาพ..."
        case .running: return "กำลังทำงาน"
        case .error: return "เกิดข้อผิดพลาด"
        }
    }
}

struct PipelineStats {
    var avgOCRTime: Double = 0
    var avgTranslateTime: Double = 0
    var avgTotalTime: Double = 0
    var totalFramesProcessed: Int = 0
    var totalTextsDetected: Int = 0
    var totalTextsTranslated: Int = 0

    private var ocrTimes: [Double] = []
    private var translateTimes: [Double] = []
    private var totalTimes: [Double] = []

    mutating func update(ocrTime: Double, translateTime: Double, totalTime: Double,
                         textsDetected: Int, textsTranslated: Int) {
        totalFramesProcessed += 1
        totalTextsDetected += textsDetected
        totalTextsTranslated += textsTranslated

        ocrTimes.append(ocrTime)
        translateTimes.append(translateTime)
        totalTimes.append(totalTime)

        if ocrTimes.count > 30 {
            ocrTimes.removeFirst()
            translateTimes.removeFirst()
            totalTimes.removeFirst()
        }

        avgOCRTime = ocrTimes.reduce(0, +) / Double(ocrTimes.count)
        avgTranslateTime = translateTimes.reduce(0, +) / Double(translateTimes.count)
        avgTotalTime = totalTimes.reduce(0, +) / Double(totalTimes.count)
    }
}

enum PipelineError: LocalizedError {
    case invalidWindow
    case captureNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidWindow: return "เลือก window ไม่ถูกต้อง"
        case .captureNotAvailable: return "ไม่สามารถจับภาพหน้าจอได้ กรุณาตรวจสอบสิทธิ์ Screen Recording"
        }
    }
}


// MARK: - SCWindow import
import ScreenCaptureKit
