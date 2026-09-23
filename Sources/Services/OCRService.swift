import Foundation
import Vision
import CoreGraphics

/// Service that performs OCR on captured frames using Vision framework
final class OCRService: @unchecked Sendable {
    private let ocrQueue = DispatchQueue(label: "com.worawalan.GameTranslator.ocr", qos: .userInitiated)
    private var isProcessing = false

    /// Minimum confidence to accept a text observation
    var minimumConfidence: Float = 0.5

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

                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: OCRFrame(texts: [], imageSize: imageSize))
                        return
                    }

                    let detectedTexts = observations.compactMap { observation -> DetectedText? in
                        guard let topCandidate = observation.topCandidates(1).first else { return nil }
                        guard topCandidate.confidence >= self.minimumConfidence else { return nil }

                        var text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }

                        // Filter out very short texts that are likely noise
                        guard text.count >= 2 else { return nil }

                        // Clean up common OCR artifacts for better translation
                        text = Self.cleanOCRText(text)
                        guard !text.isEmpty, text.count >= 2 else { return nil }

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

                    continuation.resume(returning: OCRFrame(texts: detectedTexts, imageSize: imageSize))
                }

                // Use .fast for speed — the pipeline runs at 5 FPS and .accurate is too slow
                // (~200-300ms vs ~50-100ms). Accuracy is improved instead through:
                // - Language correction (usesLanguageCorrection = true)
                // - Text cleaning (cleanOCRText) to fix common artifacts
                // - Confidence filtering (minimumConfidence)
                // - Text stabilization in TextTracker (fuzzy matching across frames)
                request.recognitionLevel = .fast
                request.recognitionLanguages = ["en"]
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = false

                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Clean up common OCR artifacts to improve translation quality
    /// without slowing down recognition
    static func cleanOCRText(_ text: String) -> String {
        var result = text

        // Remove repeated characters that OCR sometimes produces (e.g., "Helllo" → "Hello")
        // Only collapse 3+ repeats of the same character
        let pattern = "(.)\\1{2,}"
        if let regex = try? NSRegularExpression(pattern: pattern) {
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
