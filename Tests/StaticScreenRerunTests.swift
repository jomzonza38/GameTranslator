import XCTest
@testable import GameTranslator

final class StaticScreenRerunTests: XCTestCase {
    private let now: CFAbsoluteTime = 1_000

    private func delay(
        _ failedAt: [CFAbsoluteTime?], paused: Bool = false, glossaryAt: CFAbsoluteTime? = nil
    ) -> TimeInterval? {
        StaticScreenRerun.delay(
            untranslatedFailedAt: failedAt, isPaused: paused, glossaryAppliesAt: glossaryAt,
            now: now, retryDelay: 3
        )
    }

    func testNothingWaitingStaysIdle() {
        XCTAssertNil(delay([]))
    }

    func testPausedWithUntranslatedTextStaysIdle() {
        // Refused key: no busy loop on a static screen
        XCTAssertNil(delay([nil, now - 1], paused: true))
    }

    func testUnstableTextIsCheckedAgainSoon() {
        // After a reset (resume, provider/language change) text needs one more run
        XCTAssertEqual(delay([nil]), 0.5)
    }

    func testFailedTextIsRetriedWhenBackOffEnds() {
        // Failed 1 s ago, back-off 3 s → 2 s from now, not earlier
        XCTAssertEqual(try XCTUnwrap(delay([now - 1])), 2, accuracy: 0.0001)
    }

    func testSoonestWaitWins() {
        XCTAssertEqual(try XCTUnwrap(delay([now - 2.5, now - 0.5])), 0.5, accuracy: 0.0001)
    }

    func testGlossaryEditSettlingRunsEvenWhilePaused() {
        XCTAssertEqual(try XCTUnwrap(delay([nil], paused: true, glossaryAt: now + 1.2)), 1.2, accuracy: 0.0001)
    }

    func testNeverTighterThanMinimum() {
        // Back-off already over (e.g. a long OCR run): still at least the minimum delay
        XCTAssertEqual(delay([now - 10]), StaticScreenRerun.minimumDelay)
    }
}
