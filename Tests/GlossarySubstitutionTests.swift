import XCTest
@testable import GameTranslator

final class GlossarySubstitutionTests: XCTestCase {
    private let glossary = [
        GlossaryEntry(source: "Promised One", target: "ผู้ถูกเลือก"),
        GlossaryEntry(source: "Knight", target: "อัศวิน"),
        GlossaryEntry(source: "Dark Knight", target: "อัศวินทมิฬ")
    ]

    func testReplacesTermsCaseInsensitively() {
        XCTAssertEqual(
            TranslationService.applyGlossary(glossary, to: "promised one, we might go our separate ways."),
            "ผู้ถูกเลือก, we might go our separate ways."
        )
    }

    func testLongestTermWins() {
        XCTAssertEqual(
            TranslationService.applyGlossary(glossary, to: "The Dark Knight and the Knight"),
            "The อัศวินทมิฬ and the อัศวิน"
        )
    }

    func testOnlyWholeWordsAreReplaced() {
        XCTAssertEqual(TranslationService.applyGlossary(glossary, to: "Knighthood"), "Knighthood")
    }

    func testPromptAsksToLocalizeTitles() {
        let prompt = LLMPrompt.system(batch: false, context: TranslationContext(sourceLanguageName: "English"))
        XCTAssertTrue(prompt.contains("ผู้ถูกเลือก"))
        XCTAssertFalse(prompt.contains("Keep character names, proper nouns, and game terms in their original form"))
    }
}
