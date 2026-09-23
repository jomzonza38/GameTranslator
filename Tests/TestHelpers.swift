import CoreGraphics
@testable import GameTranslator

func text(_ string: String, x: CGFloat = 0.1, y: CGFloat, width: CGFloat = 0.5, height: CGFloat = 0.04) -> DetectedText {
    DetectedText(text: string, boundingBox: CGRect(x: x, y: y, width: width, height: height), confidence: 0.9)
}

func frame(_ texts: [DetectedText]) -> OCRFrame {
    OCRFrame(texts: texts, imageSize: CGSize(width: 1920, height: 1080))
}
