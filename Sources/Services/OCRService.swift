import Foundation
import Vision
import CoreGraphics

/// Service that performs OCR on captured frames using Vision framework
final class OCRService: @unchecked Sendable {
    private let ocrQueue = DispatchQueue(label: "com.worawalan.GameTranslator.ocr", qos: .userInitiated)
    private var isProcessing = false

    /// Minimum confidence to accept a text observation
    var minimumConfidence: Float = 0.5

    /// Vision recognition level (.fast or .accurate)
    var recognitionLevel: VNRequestTextRecognitionLevel = .fast

    /// Vision recognition languages, in priority order
    var recognitionLanguages: [String] = ["en-US"]

    /// Minimum characters for a text to be kept (CJK words can be a single character)
    var minimumTextLength: Int = 2

    // MARK: - First-use preparation

    /// Vision prepares (compiles) its text-recognition model for the Neural Engine on
    /// first use. The compiled model is cached per app, macOS build and **code-signing
    /// identity**; when it is missing — after a macOS update, or after a build with a
    /// different signature (ad-hoc test/Debug builds vs the certificate-signed app) used
    /// the cache — the first recognition takes ~74 s instead of ~0.1 s (T-0017).
    private static let readyLock = NSLock()
    nonisolated(unsafe) private static var visionReady = false

    /// Whether a recognition has finished in this process (Vision's model is ready)
    static var isVisionReady: Bool {
        readyLock.withLock { visionReady }
    }

    private static func markVisionReady() {
        readyLock.withLock { visionReady = true }
    }

    /// Run one small recognition in the background at launch, so a slow model
    /// preparation happens before the user starts translating. Costs ~0.1 s when the
    /// model is already prepared.
    static func warmUp(recognitionLevel: VNRequestTextRecognitionLevel, languages: [String]) {
        DispatchQueue.global(qos: .utility).async {
            guard let context = CGContext(
                data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            guard let image = context.makeImage() else { return }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = recognitionLevel
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = false

            let start = CFAbsoluteTimeGetCurrent()
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                markVisionReady()
                let seconds = CFAbsoluteTimeGetCurrent() - start
                GameLog.log(String(format: "OCR warm-up done in %.1f s%@", seconds,
                                   seconds > 5 ? " (Vision prepared its model — first use after a macOS update or a differently signed build)" : ""))
            } catch {
                GameLog.log("OCR warm-up failed: \(error.localizedDescription)")
            }
        }
    }

    /// Perform OCR on a CGImage
    /// - Parameters:
    ///   - image: The captured frame
    ///   - imageSize: Size of the captured image in pixels
    /// - Returns: Array of detected text regions
    func recognizeText(in image: CGImage, imageSize: CGSize) async throws -> OCRFrame {
        // Skip if already processing (drop frames rather than queue up)
        guard !isProcessing else {
            return OCRFrame(texts: [], imageSize: imageSize)
        }

        isProcessing = true
        defer { isProcessing = false }

        return try await withCheckedThrowingContinuation { continuation in
            ocrQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: OCRFrame(texts: [], imageSize: imageSize))
                    return
                }

                // No completion handler: `perform` is synchronous and reports errors by
                // throwing, so results are read after it returns. With a handler *and*
                // a catch, one failed request could resume the continuation twice (crash).
                let request = VNRecognizeTextRequest()

                // .fast (~50-100ms) is the default because the pipeline runs at several FPS.
                // .accurate (~200-300ms) is selectable in Settings for stylized game fonts.
                // Accuracy is further improved through language correction, text cleaning
                // (cleanOCRText), confidence filtering and TextTracker stabilization.
                request.recognitionLevel = self.recognitionLevel
                request.recognitionLanguages = self.recognitionLanguages
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = false

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    Self.markVisionReady()
                    let texts = self.detectedTexts(from: request.results ?? [])
                    continuation.resume(returning: OCRFrame(texts: texts, imageSize: imageSize))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Filter, clean and convert Vision observations (confidence, minimum length,
    /// cleanOCRText, bottom-left → top-left bounding boxes)
    private func detectedTexts(from observations: [VNRecognizedTextObservation]) -> [DetectedText] {
        observations.compactMap { observation -> DetectedText? in
            guard let topCandidate = observation.topCandidates(1).first else { return nil }
            guard topCandidate.confidence >= minimumConfidence else { return nil }

            var text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            // Filter out very short texts that are likely noise
            guard text.count >= minimumTextLength else { return nil }

            // Clean up common OCR artifacts for better translation
            text = Self.cleanOCRText(text)
            guard !text.isEmpty, text.count >= minimumTextLength else { return nil }

            // Vision returns bounding box in normalized coordinates
            // Origin is bottom-left, we need to convert to top-left
            let bbox = observation.boundingBox
            let flippedBox = CGRect(
                x: bbox.origin.x,
                y: 1.0 - bbox.origin.y - bbox.height,
                width: bbox.width,
                height: bbox.height
            )

            return DetectedText(
                text: text,
                boundingBox: flippedBox,
                confidence: topCandidate.confidence
            )
        }
    }

    /// OCR only the pixels inside `normalizedRect` (top-left origin, relative to the
    /// whole image). Text outside the rectangle is never read. Bounding boxes in the
    /// result are converted back to coordinates relative to the whole image.
    func recognizeText(in image: CGImage, imageSize: CGSize, cropTo normalizedRect: CGRect) async throws -> OCRFrame {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let pixelRect = CGRect(
            x: normalizedRect.minX * width,
            y: normalizedRect.minY * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard pixelRect.width >= 8, pixelRect.height >= 8,
              let cropped = image.cropping(to: pixelRect) else {
            return OCRFrame(texts: [], imageSize: imageSize)
        }

        let croppedFrame = try await recognizeText(in: cropped, imageSize: pixelRect.size)

        let texts = croppedFrame.texts.map { text -> DetectedText in
            let box = text.boundingBox
            let mapped = CGRect(
                x: (pixelRect.minX + box.minX * pixelRect.width) / width,
                y: (pixelRect.minY + box.minY * pixelRect.height) / height,
                width: box.width * pixelRect.width / width,
                height: box.height * pixelRect.height / height
            )
            return DetectedText(text: text.text, boundingBox: mapped, confidence: text.confidence)
        }
        return OCRFrame(texts: texts, imageSize: imageSize)
    }

    /// 3+ repeats of the same letter. Only letters — repeated punctuation is real text
    /// ("Wait...", "!!!") and must stay. Built once, not for every recognised line.
    private static let repeatedLetters = try? NSRegularExpression(pattern: "(\\p{L})\\1{2,}")

    /// Clean up common OCR artifacts to improve translation quality
    /// without slowing down recognition
    static func cleanOCRText(_ text: String) -> String {
        var result = text

        // Remove repeated characters that OCR sometimes produces (e.g., "Helllo" → "Hello")
        if let regex = repeatedLetters {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "$1$1"
            )
        }

        // Normalize whitespace (multiple spaces → single space)
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Remove leading/trailing punctuation fragments that are likely noise
        // (single stray characters like "|", "—", "~" at start/end)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "|~—–_=<>{}[]\\"))

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Estimate font size based on bounding box height and window size
    static func estimateFontSize(boundingBoxHeight: CGFloat, windowHeight: CGFloat) -> CGFloat {
        let pixelHeight = boundingBoxHeight * windowHeight
        // Approximate: font size is roughly 70-80% of pixel height
        let fontSize = pixelHeight * 0.75
        return max(10, min(fontSize, 48)) // Clamp between 10-48pt
    }
}
