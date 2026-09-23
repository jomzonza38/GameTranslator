import XCTest
@testable import GameTranslator

final class StartGenerationTests: XCTestCase {
    func testStartIsCurrentUntilSomethingElseHappens() {
        var generation = StartGeneration()
        let start = generation.begin()
        XCTAssertTrue(generation.isCurrent(start))
    }

    func testStopDuringStartOutdatesTheStart() {
        var generation = StartGeneration()
        let start = generation.begin()
        generation.invalidate()
        XCTAssertFalse(generation.isCurrent(start))
    }

    func testStopThenNewStart_oldStartStaysOutdated() {
        // stop → new start → the old start finishes (or fails): only the new one counts
        var generation = StartGeneration()
        let old = generation.begin()
        generation.invalidate()
        let new = generation.begin()
        XCTAssertFalse(generation.isCurrent(old))
        XCTAssertTrue(generation.isCurrent(new))
    }

    func testSecondStartOutdatesTheFirst() {
        var generation = StartGeneration()
        let first = generation.begin()
        let second = generation.begin()
        XCTAssertFalse(generation.isCurrent(first))
        XCTAssertTrue(generation.isCurrent(second))
    }
}
