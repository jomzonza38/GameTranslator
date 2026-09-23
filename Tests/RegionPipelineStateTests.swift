import XCTest
@testable import GameTranslator

final class RegionPipelineStateTests: XCTestCase {
    func testTypewriterTextIsNotStableUntilItStopsGrowing() {
        XCTAssertFalse(RegionPipelineState.isStable("Hello wor", previousTexts: ["Hello wo"]))
        XCTAssertFalse(RegionPipelineState.isStable("Hello world, how", previousTexts: ["Hello world"]))
        XCTAssertTrue(RegionPipelineState.isStable("Hello world", previousTexts: ["Hello world"]))
    }

    func testOCRJitterCountsAsStable() {
        XCTAssertTrue(RegionPipelineState.isStable("The bridge is broken.", previousTexts: ["The bridge is br0ken."]))
        XCTAssertTrue(RegionPipelineState.isStable("The bridge is broken", previousTexts: ["The bridge is broken."]))
    }

    func testNewTextIsNotStable() {
        XCTAssertFalse(RegionPipelineState.isStable("Brand new line", previousTexts: []))
        XCTAssertFalse(RegionPipelineState.isStable("Brand new line", previousTexts: ["Something else entirely"]))
    }

    func testSimilarTranslationReusesTranslationForMisreadLetter() {
        let state = RegionPipelineState()
        state.cachedTranslations["We must leave the village tonight."] = "เราต้องออกจากหมู่บ้านคืนนี้"

        XCTAssertEqual(
            state.similarTranslation(for: "We must leave the vil1age tonight."),
            "เราต้องออกจากหมู่บ้านคืนนี้"
        )
        XCTAssertNil(state.similarTranslation(for: "We must stay in the village tonight."))
    }

    func testSimilarTranslationChecksStaleEntries() {
        let state = RegionPipelineState()
        state.staleTranslations["Continue"] = ("ดำเนินการต่อ", CFAbsoluteTimeGetCurrent() + 10)
        XCTAssertEqual(state.similarTranslation(for: "Continue."), "ดำเนินการต่อ")
    }

    func testResetClearsEverything() {
        let state = RegionPipelineState()
        state.cachedTranslations["a"] = "b"
        state.previousFrameTexts = ["a"]
        state.failedAt["a"] = 1
        state.reset()

        XCTAssertTrue(state.cachedTranslations.isEmpty)
        XCTAssertTrue(state.previousFrameTexts.isEmpty)
        XCTAssertTrue(state.failedAt.isEmpty)
    }

    func testLevenshteinHandlesEmptyStrings() {
        XCTAssertEqual(TextTracker.levenshteinDistance("", "abc"), 3)
        XCTAssertEqual(TextTracker.levenshteinDistance("abc", ""), 3)
        XCTAssertEqual(TextTracker.levenshteinDistance("kitten", "sitting"), 3)
    }
}
