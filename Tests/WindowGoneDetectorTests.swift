import XCTest
@testable import GameTranslator

final class WindowGoneDetectorTests: XCTestCase {
    func testSingleMissIsIgnored() {
        var detector = WindowGoneDetector()
        XCTAssertFalse(detector.record(windowExists: false))
    }

    func testTwoMissesInARowMeanGone() {
        var detector = WindowGoneDetector()
        XCTAssertFalse(detector.record(windowExists: false))
        XCTAssertTrue(detector.record(windowExists: false))
    }

    func testWindowSeenAgainResetsTheCount() {
        var detector = WindowGoneDetector()
        XCTAssertFalse(detector.record(windowExists: false))
        XCTAssertFalse(detector.record(windowExists: true))
        XCTAssertFalse(detector.record(windowExists: false))
        XCTAssertTrue(detector.record(windowExists: false))
    }

    func testWindowThatAlwaysExistsIsNeverGone() {
        var detector = WindowGoneDetector()
        for _ in 0..<10 {
            XCTAssertFalse(detector.record(windowExists: true))
        }
    }
}
