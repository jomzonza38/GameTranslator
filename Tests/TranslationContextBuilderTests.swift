import XCTest
@testable import GameTranslator

final class TranslationContextBuilderTests: XCTestCase {
    private let aria = GlossaryEntry(source: "Aria", target: "อาเรีย")
    private let potion = GlossaryEntry(source: "Hi-Potion", target: "ไฮโพชั่น")

    func testGlossaryMatching() {
        XCTAssertTrue(aria.appears(in: "Where is ARIA going?"))
        XCTAssertFalse(aria.appears(in: "Nobody here"))
        XCTAssertTrue(potion.matchesExactly("  hi-potion! "))
        XCTAssertFalse(potion.matchesExactly("Buy Hi-Potion"))
        XCTAssertFalse(GlossaryEntry(source: " ", target: "x").isUsable)
    }

    func testResetAppliesUsableEntriesImmediately() {
        let builder = TranslationContextBuilder()
        builder.reset(glossary: [aria, GlossaryEntry(source: "", target: "empty")])

        XCTAssertEqual(builder.appliedGlossary, [aria])
        XCTAssertEqual(builder.fixedTranslation(for: "aria"), "อาเรีย")
        XCTAssertNil(builder.fixedTranslation(for: "Aria said hi"))
    }

    func testGlossaryEditAppliesOnlyAfterSettling() {
        let builder = TranslationContextBuilder(settleDelay: 1.5)
        builder.reset(glossary: [aria])

        XCTAssertFalse(builder.updateGlossary([aria], now: 0), "unchanged glossary")
        XCTAssertFalse(builder.updateGlossary([aria, potion], now: 10), "first sighting starts the timer")
        XCTAssertFalse(builder.updateGlossary([aria, potion], now: 11), "not settled yet")
        XCTAssertTrue(builder.updateGlossary([aria, potion], now: 11.6), "settled")
        XCTAssertEqual(builder.appliedGlossary, [aria, potion])
        XCTAssertFalse(builder.updateGlossary([aria, potion], now: 20), "already applied")
    }

    func testTypingRestartsSettleTimer() {
        let builder = TranslationContextBuilder(settleDelay: 1.5)
        builder.reset(glossary: [])

        let partial = GlossaryEntry(id: aria.id, source: "Ar", target: "อา")
        XCTAssertFalse(builder.updateGlossary([partial], now: 0))
        XCTAssertFalse(builder.updateGlossary([aria], now: 1.0), "edit restarts the timer")
        XCTAssertFalse(builder.updateGlossary([aria], now: 2.0))
        XCTAssertTrue(builder.updateGlossary([aria], now: 2.6))
    }

    func testContextSendsOnlyRelevantGlossaryAndRecentLines() {
        let builder = TranslationContextBuilder(contextLineCount: 2)
        builder.reset(glossary: [aria, potion])
        for i in 1...5 {
            builder.remember(original: "line \(i)", translation: "บรรทัด \(i)")
        }

        let context = builder.context(
            for: ["Aria waits."],
            sourceLanguageName: "English",
            gameTitle: "Game",
            includeRecentLines: true
        )
        XCTAssertEqual(context.glossary, [aria])
        XCTAssertEqual(context.recentLines.map { $0.original }, ["line 4", "line 5"])

        let withoutLines = builder.context(for: [], sourceLanguageName: "English", gameTitle: "", includeRecentLines: false)
        XCTAssertTrue(withoutLines.recentLines.isEmpty)
        XCTAssertTrue(withoutLines.glossary.isEmpty)
    }

    func testRememberSkipsImmediateRepeatsAndCapsHistory() {
        let builder = TranslationContextBuilder(contextLineCount: 2)
        builder.remember(original: "a", translation: "1")
        builder.remember(original: "a", translation: "1")
        XCTAssertEqual(builder.recentLines.count, 1)

        for i in 0..<10 {
            builder.remember(original: "x\(i)", translation: "\(i)")
        }
        XCTAssertEqual(builder.recentLines.count, 4, "keeps 2x contextLineCount")
    }
}
