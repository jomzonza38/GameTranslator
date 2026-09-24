import XCTest
import CoreGraphics
@testable import GameTranslator

final class SourceThumbnailTests: XCTestCase {
    // AC-1: crop rectangle maths

    func testBoxMapsToImagePixelsWithTopLeftOrigin() {
        // Box in the top-left quarter of a 2000×1000 image (Retina capture = 2× points)
        let rect = SourceThumbnail.pixelRect(
            for: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05), imageWidth: 2000, imageHeight: 1000, padding: 0
        )
        XCTAssertEqual(rect, CGRect(x: 200, y: 200, width: 600, height: 50))
    }

    func testPaddingIsAdded() {
        let rect = SourceThumbnail.pixelRect(
            for: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1), imageWidth: 1000, imageHeight: 1000, padding: 4
        )
        XCTAssertEqual(rect, CGRect(x: 496, y: 496, width: 108, height: 108))
    }

    func testBoxAtTheEdgeIsClampedInsideTheImage() {
        let rect = SourceThumbnail.pixelRect(
            for: CGRect(x: 0.95, y: 0.97, width: 0.2, height: 0.1), imageWidth: 1000, imageHeight: 500, padding: 4
        )
        XCTAssertEqual(rect, CGRect(x: 946, y: 481, width: 54, height: 19))
    }

    func testBoxOutsideTheImageGivesNothing() {
        XCTAssertNil(SourceThumbnail.pixelRect(
            for: CGRect(x: 1.2, y: 0.5, width: 0.1, height: 0.1), imageWidth: 1000, imageHeight: 1000, padding: 0
        ))
    }

    func testThumbnailSizeIsCappedAndNeverEnlarged() {
        XCTAssertEqual(SourceThumbnail.scaledSize(for: CGSize(width: 600, height: 60)), CGSize(width: 480, height: 48))
        XCTAssertEqual(SourceThumbnail.scaledSize(for: CGSize(width: 2000, height: 40)), CGSize(width: 560, height: 11))
        XCTAssertEqual(SourceThumbnail.scaledSize(for: CGSize(width: 100, height: 20)), CGSize(width: 100, height: 20))
    }

    func testThumbnailShowsTheBoxedPixels() throws {
        // 200×100 white image with a black 40×20 block at pixel (100, 10) from the top-left
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 100, y: 100 - 10 - 20, width: 40, height: 20)) // CGContext origin is bottom-left
        let image = context.makeImage()!

        // The box of the block, normalized with a top-left origin (like OCR boxes)
        let thumbnail = try XCTUnwrap(SourceThumbnail.make(from: image, box: CGRect(x: 0.5, y: 0.1, width: 0.2, height: 0.2)))
        XCTAssertEqual(thumbnail.width, 48)   // 40 + 2×4 padding
        XCTAssertEqual(thumbnail.height, 28)  // 20 + 2×4 padding
        XCTAssertLessThan(averageBrightness(of: thumbnail), 0.6, "mostly the black block, not white background")
    }

    private func averageBrightness(of image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let sum = stride(from: 0, to: pixels.count, by: 4).reduce(0.0) { $0 + Double(pixels[$1]) }
        return sum / Double(width * height) / 255
    }

    // AC-2: setting

    func testThumbnailSettingDefaultsToOnAndPersists() throws {
        let suite = "GameTranslatorTests.thumbnails.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(AppSettings.loadShowSourceThumbnails(defaults), "on by default")

        defaults.set(false, forKey: AppSettings.showSourceThumbnailsKey)
        XCTAssertFalse(AppSettings.loadShowSourceThumbnails(defaults), "off is remembered")

        defaults.set(true, forKey: AppSettings.showSourceThumbnailsKey)
        XCTAssertTrue(AppSettings.loadShowSourceThumbnails(defaults))
    }
}
