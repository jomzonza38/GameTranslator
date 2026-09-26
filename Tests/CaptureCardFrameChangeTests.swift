import XCTest
import CoreGraphics
@testable import GameTranslator

/// AC-1 (T-0028): frame-change logic on the capture card picture. The picture is
/// translated through the window pipeline, so the exact fingerprint + FrameChangeFilter
/// decide what goes to OCR.
final class CaptureCardFrameChangeTests: XCTestCase {
    private let width = 160
    private let height = 90
    private let window = CGRect(x: 100, y: 100, width: 1280, height: 720)

    /// A "Switch picture": dark background with a dialog box, BGRA
    private func picture() -> [UInt8] {
        var bytes = [UInt8](repeating: 20, count: width * height * 4)
        for y in 60..<85 {
            for x in 10..<150 { setPixel(&bytes, x, y, 235) }
        }
        return bytes
    }

    /// Draw one "character" (a small dark block) at text position `index` of `line`
    private func typeCharacter(_ bytes: inout [UInt8], line: Int, index: Int) {
        let x0 = 14 + index * 6
        let y0 = 63 + line * 8
        for y in y0..<(y0 + 5) {
            for x in x0..<(x0 + 4) { setPixel(&bytes, x, y, 30) }
        }
    }

    private func setPixel(_ bytes: inout [UInt8], _ x: Int, _ y: Int, _ value: UInt8) {
        let i = (y * width + x) * 4
        bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = 255
    }

    private func fingerprint(_ bytes: [UInt8]) -> UInt64 {
        bytes.withUnsafeBytes {
            FrameFingerprint.of(bytes: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4, bytesPerPixel: 4)
        }
    }

    /// The filter after the given picture was sent to OCR
    private func filter(after bytes: [UInt8]) -> FrameChangeFilter {
        var filter = FrameChangeFilter()
        filter.recordProcessed(fingerprint(bytes), windowFrame: window)
        return filter
    }

    func testSamePictureIsNotOCRdAgain() {
        var text = picture()
        typeCharacter(&text, line: 0, index: 0)
        let filter = filter(after: text)
        XCTAssertFalse(filter.shouldProcess(fingerprint(text), windowFrame: window, workWaiting: false))
    }

    func testNewLineOfTextIsAChange() {
        var before = picture()
        for i in 0..<10 { typeCharacter(&before, line: 0, index: i) }
        var after = before
        for i in 0..<6 { typeCharacter(&after, line: 1, index: i) }
        XCTAssertTrue(filter(after: before).shouldProcess(fingerprint(after), windowFrame: window, workWaiting: false))
    }

    /// Typewriter text: one more character is a new picture
    func testOneAddedCharacterIsAChange() {
        var before = picture()
        for i in 0..<10 { typeCharacter(&before, line: 0, index: i) }
        var after = before
        typeCharacter(&after, line: 0, index: 10)
        XCTAssertTrue(filter(after: before).shouldProcess(fingerprint(after), windowFrame: window, workWaiting: false))
    }

    /// Resizing the picture window or going full screen must reposition the boxes
    func testResizedWindowIsProcessedEvenWithTheSamePicture() {
        let bytes = picture()
        let bigger = CGRect(x: 0, y: 0, width: 1470, height: 827)
        XCTAssertTrue(filter(after: bytes).shouldProcess(fingerprint(bytes), windowFrame: bigger, workWaiting: false))
    }

    // MARK: FrameStats (diagnostics log)

    func testFrameStatsReportsOncePerInterval() {
        var stats = FrameStats()
        XCTAssertNil(stats.record(changed: true, now: 100))
        stats.processed += 1
        XCTAssertNil(stats.record(changed: false, now: 105))
        XCTAssertNil(stats.record(changed: false, now: 109.9))
        XCTAssertEqual(stats.record(changed: true, now: 110),
                       "4 received, 2 with changed pixels, 1 sent to OCR in 10 s")
        // Counting starts again
        XCTAssertNil(stats.record(changed: false, now: 111))
        XCTAssertEqual(stats.record(changed: false, now: 120),
                       "2 received, 0 with changed pixels, 0 sent to OCR in 10 s")
    }
}
