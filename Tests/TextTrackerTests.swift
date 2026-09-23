import XCTest
@testable import GameTranslator

final class TextTrackerTests: XCTestCase {
    func testFirstFrameIsAllNew() {
        let tracker = TextTracker()
        let result = tracker.diff(currentFrame: frame([text("Hello", y: 0.1), text("World", y: 0.5)]))

        XCTAssertEqual(result.newTexts.map(\.text), ["Hello", "World"])
        XCTAssertTrue(result.unchangedTexts.isEmpty)
        XCTAssertTrue(result.removedTexts.isEmpty)
    }

    func testSameFrameIsUnchanged() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("Hello there", y: 0.1)]))
        let result = tracker.diff(currentFrame: frame([text("Hello there", y: 0.1)]))

        XCTAssertEqual(result.unchangedTexts.map(\.text), ["Hello there"])
        XCTAssertFalse(result.hasChanges)
        XCTAssertTrue(result.textsNeedingTranslation.isEmpty)
    }

    func testSmallOCRJitterCountsAsUnchanged() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("The quick brown fox jumps", y: 0.1)]))
        // One character misread, box shifted slightly
        let result = tracker.diff(currentFrame: frame([text("The quick brown f0x jumps", y: 0.105)]))

        XCTAssertEqual(result.unchangedTexts.count, 1)
        XCTAssertTrue(result.textsNeedingTranslation.isEmpty)
    }

    func testDifferentTextAtSamePositionIsChanged() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("Welcome to the village", y: 0.8)]))
        let result = tracker.diff(currentFrame: frame([text("The bridge is broken", y: 0.8)]))

        XCTAssertEqual(result.changedTexts.count, 1)
        XCTAssertEqual(result.changedTexts.first?.old.text, "Welcome to the village")
        XCTAssertEqual(result.textsNeedingTranslation.map(\.text), ["The bridge is broken"])
    }

    func testMovedTextIsUnchanged() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("Scrolling line", y: 0.2)]))
        let result = tracker.diff(currentFrame: frame([text("Scrolling line", y: 0.6)]))

        XCTAssertEqual(result.unchangedTexts.map(\.text), ["Scrolling line"])
        XCTAssertTrue(result.newTexts.isEmpty)
        XCTAssertTrue(result.removedTexts.isEmpty)
    }

    func testDisappearedTextIsRemoved() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("Stays", y: 0.1), text("Goes away", y: 0.5)]))
        let result = tracker.diff(currentFrame: frame([text("Stays", y: 0.1)]))

        XCTAssertEqual(result.removedTexts.map(\.text), ["Goes away"])
        XCTAssertTrue(result.hasChanges)
    }

    func testResetTreatsNextFrameAsNew() {
        let tracker = TextTracker()
        _ = tracker.diff(currentFrame: frame([text("Hello", y: 0.1)]))
        tracker.reset()
        let result = tracker.diff(currentFrame: frame([text("Hello", y: 0.1)]))

        XCTAssertEqual(result.newTexts.map(\.text), ["Hello"])
    }
}
