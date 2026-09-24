import XCTest
import CoreGraphics
@testable import GameTranslator

/// AC-2 (T-0020): image → screen mapping
final class CaptureGeometryTests: XCTestCase {
    private func assertRect(_ a: CGRect, _ b: CGRect, accuracy: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, file: file, line: line)
    }

    /// Full mapping as the app does it: buffer box → content box → screen
    private func map(_ bufferBox: CGRect, buffer: CGSize, content: CGRect, window: CGRect) -> CGRect {
        CaptureGeometry.screenRect(
            forContentBox: CaptureGeometry.boxInContent(bufferBox, bufferSize: buffer, content: content),
            windowFrame: window
        )
    }

    // Buffer equal to the window

    func testBufferEqualToWindow() {
        let window = CGRect(x: 100, y: 50, width: 800, height: 600)
        let buffer = CGSize(width: 1600, height: 1200)
        let content = CaptureGeometry.contentPixelRect(contentRect: nil, contentScale: nil, scaleFactor: nil, bufferSize: buffer)
        XCTAssertEqual(content, CGRect(origin: .zero, size: buffer))
        XCTAssertFalse(CaptureGeometry.contentIsInset(content, bufferSize: buffer))

        let screen = map(CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05), buffer: buffer, content: content, window: window)
        assertRect(screen, CGRect(x: 300, y: 350, width: 80, height: 30))
    }

    func testContentFillingTheBufferIsNotCropped() {
        // Frame info in window points (1× content scale, 2× display) covering the buffer
        let buffer = CGSize(width: 1600, height: 1200)
        let content = CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), contentScale: 1, scaleFactor: 2, bufferSize: buffer
        )
        XCTAssertFalse(CaptureGeometry.contentIsInset(content, bufferSize: buffer))
    }

    // Content letterboxed / scaled inside the buffer

    func testWindowScaledAndLetterboxedInsideTheBuffer() {
        // Stream configured for a 1000×500 pt window (2000×1000 px); the window is now
        // 1600×1200 pt, so ScreenCaptureKit scales it by 0.4167 (×2 display) and
        // centres it: content at x 333…1667 px of the buffer
        let buffer = CGSize(width: 2000, height: 1000)
        let contentScale: CGFloat = 1000.0 / 2400.0
        let content = CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 400, y: 0, width: 1600, height: 1200),
            contentScale: contentScale, scaleFactor: 2, bufferSize: buffer
        )
        assertRect(content, CGRect(x: 333, y: 0, width: 1334, height: 1000), accuracy: 1.5)
        XCTAssertTrue(CaptureGeometry.contentIsInset(content, bufferSize: buffer))

        // Text at window points (400, 300, 160×60) → where it lands in the buffer
        let exact = CGRect(x: 1000.0 / 3, y: 0, width: 4000.0 / 3, height: 1000) // unrounded content
        let bufferBox = CGRect(
            x: (exact.minX + 0.25 * exact.width) / buffer.width,
            y: (exact.minY + 0.25 * exact.height) / buffer.height,
            width: 0.1 * exact.width / buffer.width,
            height: 0.05 * exact.height / buffer.height
        )
        let window = CGRect(x: 50, y: 40, width: 1600, height: 1200)
        assertRect(map(bufferBox, buffer: buffer, content: content, window: window),
                   CGRect(x: 450, y: 340, width: 160, height: 60), accuracy: 2)

        // Mapping the buffer box straight onto the window (the old behaviour) is off
        let naive = CaptureGeometry.screenRect(forContentBox: bufferBox, windowFrame: window)
        XCTAssertGreaterThan(abs(naive.minX - 450), 50)
    }

    func testContentRectAlreadyInPixelsIsTakenAsIs() {
        let buffer = CGSize(width: 2000, height: 1000)
        let content = CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 333, y: 0, width: 1334, height: 1000), contentScale: 0.4167, scaleFactor: 2, bufferSize: buffer
        )
        // ×scale candidates don't fit in the buffer; the rect as given does
        assertRect(content, CGRect(x: 333, y: 0, width: 1334, height: 1000))
    }

    // Window size changed since start

    func testWindowSizeChangedSinceStartNeedsResize() {
        let configured = CaptureGeometry.captureSize(forWindow: CGSize(width: 1280, height: 800))
        XCTAssertEqual(configured.width, 2560)
        XCTAssertEqual(configured.height, 1600)

        XCTAssertFalse(CaptureGeometry.needsResize(configured: configured, window: CGSize(width: 1280, height: 800)))
        XCTAssertFalse(CaptureGeometry.needsResize(configured: configured, window: CGSize(width: 1280.5, height: 800)), "rounding noise")
        XCTAssertTrue(CaptureGeometry.needsResize(configured: configured, window: CGSize(width: 1470, height: 956)), "went full-screen")
    }

    func testAfterResizeTheBufferEqualsTheWindowAgain() {
        // Once reconfigured, the full-screen window fills the new buffer
        let window = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let size = CaptureGeometry.captureSize(forWindow: window.size)
        let buffer = CGSize(width: size.width, height: size.height)
        let content = CaptureGeometry.contentPixelRect(
            contentRect: CGRect(origin: .zero, size: window.size), contentScale: 1, scaleFactor: 2, bufferSize: buffer
        )
        let box = CGRect(x: 382.0 / 1470, y: 309.0 / 956, width: 218.0 / 1470, height: 33.0 / 956)
        assertRect(map(box, buffer: buffer, content: content, window: window), CGRect(x: 382, y: 309, width: 218, height: 33))
    }
}
