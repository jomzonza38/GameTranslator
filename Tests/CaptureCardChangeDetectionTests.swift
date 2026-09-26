import XCTest
import CoreGraphics
@testable import GameTranslator

/// AC-1 (T-0034): noise-tolerant change check in capture card mode, per region;
/// OCR pacing; capture size capped at the picture's resolution.
final class CaptureCardChangeDetectionTests: XCTestCase {
    private let width = 1280
    private let height = 720

    // MARK: Picture helpers (BGRA)

    /// Dark game scene with a light dialogue box at the bottom
    private func scene() -> [UInt8] {
        var bytes = [UInt8](repeating: 40, count: width * height * 4)
        fill(&bytes, CGRect(x: 80, y: 520, width: 1120, height: 170), 230)
        return bytes
    }

    private func fill(_ bytes: inout [UInt8], _ rect: CGRect, _ value: UInt8) {
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * width + x) * 4
                bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = 255
            }
        }
    }

    /// One character (10×14 px glyph) at position `index` of text line `line`
    private func typeCharacter(_ bytes: inout [UInt8], line: Int, index: Int) {
        fill(&bytes, CGRect(x: 110 + index * 14, y: 545 + line * 30, width: 10, height: 14), 25)
    }

    /// Capture noise: every channel of every pixel moved by up to ±`amount`
    private func addNoise(_ bytes: inout [UInt8], amount: Int, seed: UInt64) {
        var state = seed
        for i in stride(from: 0, to: bytes.count, by: 4) {
            for c in 0..<3 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let delta = Int(state >> 33) % (2 * amount + 1) - amount
                bytes[i + c] = UInt8(max(0, min(255, Int(bytes[i + c]) + delta)))
            }
        }
    }

    private func grid(_ bytes: [UInt8]) -> LumaGrid {
        bytes.withUnsafeBytes {
            LumaGrid.of(bytes: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4)
        }
    }

    private func detector(after bytes: [UInt8], areas: [LumaChangeDetector.Area]) -> LumaChangeDetector {
        var detector = LumaChangeDetector()
        detector.record(grid(bytes), areas: areas)
        return detector
    }

    // MARK: Whole picture

    func testIdenticalPictureIsNotAChange() {
        var picture = scene()
        typeCharacter(&picture, line: 0, index: 0)
        let d = detector(after: picture, areas: [.whole])
        XCTAssertTrue(d.changedAreas(grid(picture), areas: [(.whole, nil)]).isEmpty)
    }

    func testCaptureNoiseIsNotAChange() {
        var picture = scene()
        for i in 0..<20 { typeCharacter(&picture, line: 0, index: i) }
        let d = detector(after: picture, areas: [.whole])
        var noisy = picture
        addNoise(&noisy, amount: 6, seed: 42)
        XCTAssertTrue(d.changedAreas(grid(noisy), areas: [(.whole, nil)]).isEmpty)
    }

    func testNewLineOfTextIsAChange() {
        var before = scene()
        for i in 0..<20 { typeCharacter(&before, line: 0, index: i) }
        var after = before
        for i in 0..<8 { typeCharacter(&after, line: 1, index: i) }
        let d = detector(after: before, areas: [.whole])
        XCTAssertEqual(d.changedAreas(grid(after), areas: [(.whole, nil)]), [.whole])
    }

    /// Typewriter text: one more character, with noise on top, is still a change
    func testOneAddedCharacterIsAChangeEvenWithNoise() {
        var before = scene()
        for i in 0..<20 { typeCharacter(&before, line: 0, index: i) }
        var after = before
        typeCharacter(&after, line: 0, index: 20)
        addNoise(&after, amount: 6, seed: 7)
        let d = detector(after: before, areas: [.whole])
        XCTAssertEqual(d.changedAreas(grid(after), areas: [(.whole, nil)]), [.whole])
    }

    func testAreaNeverReadCountsAsChanged() {
        let d = LumaChangeDetector()
        XCTAssertEqual(d.changedAreas(grid(scene()), areas: [(.whole, nil)]), [.whole])
    }

    // MARK: Regions

    func testChangeOutsideARegionDoesNotTriggerIt() {
        let dialogue = UUID(), top = UUID()
        let dialogueRect = CGRect(x: 80.0 / 1280, y: 520.0 / 720, width: 1120.0 / 1280, height: 170.0 / 720)
        let topRect = CGRect(x: 0, y: 0, width: 1, height: 0.2)
        let areas: [(LumaChangeDetector.Area, CGRect?)] = [(.region(dialogue), dialogueRect), (.region(top), topRect)]

        let before = scene()
        let d = detector(after: before, areas: [.region(dialogue), .region(top)])

        // Something moves in the middle of the scene (character animation): no region changed
        var animated = before
        fill(&animated, CGRect(x: 600, y: 250, width: 80, height: 120), 200)
        XCTAssertTrue(d.changedAreas(grid(animated), areas: areas).isEmpty)

        // New text in the dialogue box: only that region
        var typed = animated
        typeCharacter(&typed, line: 0, index: 3)
        XCTAssertEqual(d.changedAreas(grid(typed), areas: areas), [.region(dialogue)])
    }

    func testGridCellsForARect() {
        let g = LumaGrid(columns: 4, rows: 2, values: [Float](repeating: 0, count: 8))
        XCTAssertEqual(g.cells(in: CGRect(x: 0, y: 0, width: 0.25, height: 0.5)), [0])
        XCTAssertEqual(g.cells(in: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)), [6, 7])
        XCTAssertEqual(g.cells(in: nil).count, 8)
        XCTAssertEqual(g.cells(in: CGRect(x: 2, y: 2, width: 1, height: 1)), [])
    }

    func testContentRectLimitsTheGrid() {
        // Picture in the lower part of the buffer only (title bar above it)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        fill(&bytes, CGRect(x: 0, y: 60, width: 1280, height: 660), 200)
        let g = bytes.withUnsafeBytes {
            LumaGrid.of(bytes: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4,
                        content: CGRect(x: 0, y: 60, width: 1280, height: 660))
        }
        XCTAssertTrue(g.values.allSatisfy { abs($0 - 200) < 1 })
    }

    // MARK: OCR pacer

    func testPacerSlowsDownAfterTheSameTextAndSpeedsUpOnNewText() {
        var pacer = OCRPacer()
        pacer.recordRun(signature: "Hello", at: 0)
        XCTAssertEqual(pacer.delayBeforeNextRun(now: 0.1), 0)
        pacer.recordRun(signature: "Hello", at: 0.2)
        pacer.recordRun(signature: "Hello", at: 0.4)
        XCTAssertEqual(pacer.delayBeforeNextRun(now: 0.5), 0, "two repeats: still full rate")
        pacer.recordRun(signature: "Hello", at: 0.6)
        XCTAssertTrue(pacer.isSlowed)
        XCTAssertEqual(pacer.delayBeforeNextRun(now: 0.7), 0.9, accuracy: 0.0001)
        XCTAssertEqual(pacer.delayBeforeNextRun(now: 2.0), 0)
        pacer.recordRun(signature: "Next line", at: 2.0)
        XCTAssertFalse(pacer.isSlowed)
        XCTAssertEqual(pacer.delayBeforeNextRun(now: 2.1), 0)
    }

    // MARK: Capture size (AC-2)

    func testCaptureCardModeNeverCapturesAboveThePicture() {
        // MacBook Air full screen: 1470×956 pt window → 2× would be 2940×1912
        let size = CaptureGeometry.captureSize(forWindow: CGSize(width: 1470, height: 956),
                                               limit: CGSize(width: 1920, height: 1080))
        XCTAssertLessThanOrEqual(size.width, 1920)
        XCTAssertLessThanOrEqual(size.height, 1080)
        XCTAssertEqual(Double(size.width) / Double(size.height), 1470.0 / 956.0, accuracy: 0.01)
    }

    func testSmallWindowIsStillCapturedAtTwice() {
        let size = CaptureGeometry.captureSize(forWindow: CGSize(width: 640, height: 388),
                                               limit: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(size, CaptureGeometry.PixelSize(width: 1280, height: 776))
    }

    func testGameWindowsKeepTwice() {
        XCTAssertEqual(CaptureGeometry.captureSize(forWindow: CGSize(width: 1470, height: 956)),
                       CaptureGeometry.PixelSize(width: 2940, height: 1912))
    }
}
