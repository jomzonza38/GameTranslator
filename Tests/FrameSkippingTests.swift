import XCTest
import CoreGraphics
@testable import GameTranslator

final class FrameFingerprintTests: XCTestCase {
    /// BGRA pixels, `padding` extra bytes at the end of every row (like CVPixelBuffer rows)
    private func pixels(width: Int, height: Int, padding: Int = 0, fill: UInt8 = 200) -> (bytes: [UInt8], bytesPerRow: Int) {
        let bytesPerRow = width * 4 + padding
        var bytes = [UInt8](repeating: fill, count: bytesPerRow * height)
        // Padding holds garbage that must not count
        for row in 0..<height where padding > 0 {
            for i in 0..<padding { bytes[row * bytesPerRow + width * 4 + i] = UInt8((row * 31 + i) & 255) }
        }
        return (bytes, bytesPerRow)
    }

    private func fingerprint(_ p: (bytes: [UInt8], bytesPerRow: Int), width: Int, height: Int) -> UInt64 {
        p.bytes.withUnsafeBytes {
            FrameFingerprint.of(bytes: $0.baseAddress!, width: width, height: height, bytesPerRow: p.bytesPerRow, bytesPerPixel: 4)
        }
    }

    func testSamePixelsSameFingerprint() {
        XCTAssertEqual(
            fingerprint(pixels(width: 64, height: 32), width: 64, height: 32),
            fingerprint(pixels(width: 64, height: 32), width: 64, height: 32)
        )
    }

    func testOneChangedPixelChangesFingerprint() {
        let a = pixels(width: 64, height: 32)
        var b = a
        b.bytes[17 * b.bytesPerRow + 40 * 4] = 0 // one channel of one pixel
        XCTAssertNotEqual(fingerprint(a, width: 64, height: 32), fingerprint(b, width: 64, height: 32))
    }

    func testRowPaddingIsIgnored() {
        XCTAssertEqual(
            fingerprint(pixels(width: 64, height: 32, padding: 0), width: 64, height: 32),
            fingerprint(pixels(width: 64, height: 32, padding: 16), width: 64, height: 32)
        )
    }

    func testSizeIsPartOfTheFingerprint() {
        // Same bytes, read as 64×32 or 32×64
        let p = pixels(width: 64, height: 32)
        XCTAssertNotEqual(
            fingerprint(p, width: 64, height: 32),
            p.bytes.withUnsafeBytes {
                FrameFingerprint.of(bytes: $0.baseAddress!, width: 32, height: 64, bytesPerRow: 32 * 4, bytesPerPixel: 4)
            }
        )
    }
}

final class FrameChangeFilterTests: XCTestCase {
    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testNewFrameIsProcessed() {
        let filter = FrameChangeFilter()
        XCTAssertTrue(filter.shouldProcess(1, windowFrame: window, workWaiting: false))
    }

    func testUnchangedFrameIsSkipped() {
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        XCTAssertFalse(filter.shouldProcess(1, windowFrame: window, workWaiting: false))
    }

    func testChangedFrameIsProcessed() {
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        XCTAssertTrue(filter.shouldProcess(2, windowFrame: window, workWaiting: false))
    }

    func testUnchangedFrameIsProcessedWhileWorkIsWaiting() {
        // T-0015: text waiting to become stable needs another run of the same pixels
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        XCTAssertTrue(filter.shouldProcess(1, windowFrame: window, workWaiting: true))
    }

    func testMovedWindowIsProcessed() {
        // Same pixels, but the overlay must follow the window
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        XCTAssertTrue(filter.shouldProcess(1, windowFrame: window.offsetBy(dx: 50, dy: 0), workWaiting: false))
    }

    func testBlinkingBetweenStatesIsSkippedAfterBothWereSeen() {
        // Caret on (1) / off (2) alternating
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        XCTAssertTrue(filter.shouldProcess(2, windowFrame: window, workWaiting: false))
        filter.recordProcessed(2, windowFrame: window)
        for fingerprint: UInt64 in [1, 2, 1, 2] {
            XCTAssertFalse(filter.shouldProcess(fingerprint, windowFrame: window, workWaiting: false))
        }
    }

    func testOnlyRecentFramesAreRemembered() {
        var filter = FrameChangeFilter(capacity: 3)
        for fingerprint: UInt64 in [1, 2, 3, 4] {
            filter.recordProcessed(fingerprint, windowFrame: window)
        }
        XCTAssertTrue(filter.shouldProcess(1, windowFrame: window, workWaiting: false), "oldest was forgotten")
        XCTAssertFalse(filter.shouldProcess(4, windowFrame: window, workWaiting: false))
    }

    func testResetForgetsEverything() {
        var filter = FrameChangeFilter()
        filter.recordProcessed(1, windowFrame: window)
        filter.reset()
        XCTAssertTrue(filter.shouldProcess(1, windowFrame: window, workWaiting: false))
    }
}
