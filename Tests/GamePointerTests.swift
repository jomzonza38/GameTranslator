import XCTest
import CoreGraphics
@testable import GameTranslator

final class GamePointerTests: XCTestCase {
    private let dialog = (id: "full|Hello#0", sourceRect: CGRect(x: 100, y: 100, width: 400, height: 60))
    private let word = (id: "full|Hi#0", sourceRect: CGRect(x: 120, y: 110, width: 60, height: 20))
    private let okTop = (id: "full|OK#0", sourceRect: CGRect(x: 600, y: 100, width: 50, height: 20))
    private let okBottom = (id: "full|OK#1", sourceRect: CGRect(x: 600, y: 500, width: 50, height: 20))

    // AC-1

    func testPointInsideATextFindsIt() {
        XCTAssertEqual(GamePointer.entryID(at: CGPoint(x: 300, y: 130), in: [dialog, okTop]), dialog.id)
    }

    func testPointOutsideFindsNothing() {
        XCTAssertNil(GamePointer.entryID(at: CGPoint(x: 50, y: 50), in: [dialog, okTop]))
    }

    func testOverlappingTextsPickTheSmallest() {
        XCTAssertEqual(GamePointer.entryID(at: CGPoint(x: 150, y: 120), in: [dialog, word]), word.id)
    }

    func testSameTextTwicePicksTheCopyUnderTheMouse() {
        XCTAssertEqual(GamePointer.entryID(at: CGPoint(x: 620, y: 510), in: [okTop, okBottom]), okBottom.id)
        XCTAssertEqual(GamePointer.entryID(at: CGPoint(x: 620, y: 110), in: [okTop, okBottom]), okTop.id)
    }

    func testMouseToCGPointConversion() {
        // AppKit origin bottom-left of a 900 pt tall primary display
        XCTAssertEqual(ScreenCoordinates.cgPoint(fromAppKit: CGPoint(x: 10, y: 800), primaryDisplayHeight: 900), CGPoint(x: 10, y: 100))
    }

    // AC-2

    func testMovingEveryTickNeverSelects() {
        var tracker = PointerRestTracker()
        // Sweeping 20 pt per 0.1 s tick along the same long text
        for step in 0..<30 {
            let selected = tracker.update(hit: "A", at: CGPoint(x: 100 + CGFloat(step) * 20, y: 100), now: Double(step) * 0.1)
            XCTAssertNil(selected, "step \(step)")
        }
    }

    func testSweepingAcrossTextsNeverSelects() {
        var tracker = PointerRestTracker()
        for step in 0..<30 {
            let hit = ["A", "B", nil, "C"][step % 4]
            XCTAssertNil(tracker.update(hit: hit, at: CGPoint(x: CGFloat(step) * 30, y: 0), now: Double(step) * 0.1))
        }
    }

    func testRestingForTheDelaySelects() {
        var tracker = PointerRestTracker()
        let point = CGPoint(x: 300, y: 130)
        XCTAssertNil(tracker.update(hit: "A", at: point, now: 0))
        XCTAssertNil(tracker.update(hit: "A", at: point, now: 0.2))
        XCTAssertNil(tracker.update(hit: "A", at: CGPoint(x: 302, y: 131), now: 0.3), "tiny jitter is fine")
        XCTAssertEqual(tracker.update(hit: "A", at: point, now: 0.4), "A")
    }

    func testLeavingClearsAfterTheDelayNotAtOnce() {
        var tracker = PointerRestTracker()
        let on = CGPoint(x: 300, y: 130)
        _ = tracker.update(hit: "A", at: on, now: 0)
        XCTAssertEqual(tracker.update(hit: "A", at: on, now: 0.5), "A")

        let off = CGPoint(x: 50, y: 50)
        XCTAssertEqual(tracker.update(hit: nil, at: off, now: 0.6), "A", "still marked right after leaving")
        XCTAssertEqual(tracker.update(hit: nil, at: off, now: 0.8), "A")
        XCTAssertNil(tracker.update(hit: nil, at: off, now: 1.0), "cleared after resting off the text")
    }

    func testMovingToAnotherTextSwitchesAfterTheDelay() {
        var tracker = PointerRestTracker()
        _ = tracker.update(hit: "A", at: CGPoint(x: 0, y: 0), now: 0)
        _ = tracker.update(hit: "A", at: CGPoint(x: 0, y: 0), now: 0.5)
        XCTAssertEqual(tracker.update(hit: "B", at: CGPoint(x: 0, y: 100), now: 0.6), "A")
        XCTAssertEqual(tracker.update(hit: "B", at: CGPoint(x: 0, y: 100), now: 1.0), "B")
    }

    // AC-3

    func testSettingDefaultsToOnAndPersists() throws {
        let suite = "GameTranslatorTests.pointer.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AppSettings.loadPanelFollowsGamePointer(defaults))
        defaults.set(false, forKey: AppSettings.panelFollowsGamePointerKey)
        XCTAssertFalse(AppSettings.loadPanelFollowsGamePointer(defaults))
    }
}

@MainActor
final class PanelPointedEntryTests: XCTestCase {
    private func region(_ text: String, at rect: CGRect) -> TranslatedRegion {
        TranslatedRegion(originalText: text, translatedText: "แปล \(text)", screenRect: rect, fontSize: 14)
    }

    func testPointedEntryIsClearedWhenItsTextIsGone() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: CGRect(x: 0, y: 0, width: 100, height: 20)),
                           region("World", at: CGRect(x: 0, y: 50, width: 100, height: 20))])
        let hello = try XCTUnwrap(data.entries.first { $0.original == "Hello" }).id
        data.setPointed(hello)
        XCTAssertEqual(data.pointedID, hello)

        data.update(from: [region("World", at: CGRect(x: 0, y: 50, width: 100, height: 20))])
        XCTAssertNil(data.pointedID)
    }

    func testUnknownEntryIsNotMarkedAndStopClearsTheMark() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: CGRect(x: 0, y: 0, width: 100, height: 20))])
        data.setPointed("full|Nope#0")
        XCTAssertNil(data.pointedID)

        data.setPointed(try XCTUnwrap(data.entries.first).id)
        data.clear() // stop / game closed → panel hide()
        XCTAssertNil(data.pointedID)
    }
}
