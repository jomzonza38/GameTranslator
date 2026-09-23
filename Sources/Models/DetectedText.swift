import Foundation
import CoreGraphics

/// Represents a text region detected by OCR
struct DetectedText: Identifiable, Equatable {
    let id: UUID
    /// The recognized text string
    let text: String
    /// Bounding box in normalized coordinates (0...1) relative to the captured image
    let boundingBox: CGRect
    /// OCR confidence score (0...1)
    let confidence: Float
    /// Timestamp when this text was detected
    let detectedAt: Date

    init(text: String, boundingBox: CGRect, confidence: Float) {
        self.id = UUID()
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.detectedAt = Date()
    }

    static func == (lhs: DetectedText, rhs: DetectedText) -> Bool {
        lhs.text == rhs.text && lhs.boundingBox.approximately(equals: rhs.boundingBox, tolerance: 0.05)
    }
}

/// Represents a frame of OCR results
struct OCRFrame {
    let texts: [DetectedText]
    let timestamp: Date
    let imageSize: CGSize

    init(texts: [DetectedText], imageSize: CGSize) {
        self.texts = texts
        self.timestamp = Date()
        self.imageSize = imageSize
    }
}

// MARK: - CGRect Extension for approximate comparison
extension CGRect {
    func approximately(equals other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) < tolerance &&
        abs(origin.y - other.origin.y) < tolerance &&
        abs(size.width - other.size.width) < tolerance &&
        abs(size.height - other.size.height) < tolerance
    }
}
