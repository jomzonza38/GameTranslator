import XCTest
import AppKit
@testable import GameTranslator

/// Runs real Vision OCR on generated images (no screen capture or permission needed)
final class OCRServiceTests: XCTestCase {
    /// White image with black text drawn in its top half
    private func image(text: String?, width: Int = 800, height: Int = 200) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let text {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            // CGContext origin is bottom-left: y = 120 puts the text in the top half
            NSAttributedString(string: text, attributes: attributes).draw(at: CGPoint(x: 40, y: 120))
            NSGraphicsContext.restoreGraphicsState()
        }
        return context.makeImage()!
    }

    private func makeService() -> OCRService {
        let service = OCRService()
        service.recognitionLevel = .accurate
        service.recognitionLanguages = ["en-US"]
        return service
    }

    func testRecognizesTextAndKeepsTopLeftCoordinates() async throws {
        let frame = try await makeService().recognizeText(
            in: image(text: "HELLO WORLD"),
            imageSize: CGSize(width: 800, height: 200)
        )

        let hello = try XCTUnwrap(frame.texts.first { $0.text.uppercased().contains("HELLO") })
        // Drawn in the top half → top-left-origin box must be in the upper half
        XCTAssertLessThan(hello.boundingBox.midY, 0.5)
        XCTAssertLessThan(hello.boundingBox.minX, 0.2)
    }

    func testBlankImageReturnsNoTextWithoutError() async throws {
        let frame = try await makeService().recognizeText(
            in: image(text: nil),
            imageSize: CGSize(width: 800, height: 200)
        )
        XCTAssertTrue(frame.texts.isEmpty)
    }

    func testCroppedRegionMapsBackToWholeImage() async throws {
        // Crop to the top half, where the text is; boxes come back relative to the whole image
        let frame = try await makeService().recognizeText(
            in: image(text: "HELLO WORLD"),
            imageSize: CGSize(width: 800, height: 200),
            cropTo: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        )

        let hello = try XCTUnwrap(frame.texts.first { $0.text.uppercased().contains("HELLO") })
        XCTAssertLessThan(hello.boundingBox.maxY, 0.55)
    }

    func testVisionIsReadyAfterARecognition() async throws {
        // T-0017: the "preparing OCR" status is shown only until one recognition finished
        _ = try await makeService().recognizeText(in: image(text: nil), imageSize: CGSize(width: 800, height: 200))
        XCTAssertTrue(OCRService.isVisionReady)
    }

    func testPreparingStatusIsThai() {
        XCTAssertTrue(PipelineStatus.preparingOCR.displayName.hasPrefix("กำลังเตรียม OCR"))
    }
}
