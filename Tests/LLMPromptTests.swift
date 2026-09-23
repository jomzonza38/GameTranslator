import XCTest
@testable import GameTranslator

final class LLMPromptTests: XCTestCase {
    func testNumbered() {
        XCTAssertEqual(LLMPrompt.numbered(["a", "b"]), "[1] a\n[2] b")
    }

    func testParseNumberedInOrder() {
        let reply = "[1] สวัสดี\n[2] ลาก่อน"
        XCTAssertEqual(LLMPrompt.parseNumbered(reply, count: 2), ["สวัสดี", "ลาก่อน"])
    }

    func testParseNumberedOutOfOrderAndBlankLines() {
        let reply = "\n[2] สอง\n\n[1] หนึ่ง\n"
        XCTAssertEqual(LLMPrompt.parseNumbered(reply, count: 2), ["หนึ่ง", "สอง"])
    }

    func testParseNumberedMissingLineReturnsNil() {
        XCTAssertNil(LLMPrompt.parseNumbered("[1] หนึ่ง", count: 2))
        XCTAssertNil(LLMPrompt.parseNumbered("[1] หนึ่ง\n[2]", count: 2))
        XCTAssertNil(LLMPrompt.parseNumbered("no numbering here", count: 1))
    }

    func testSystemPromptIncludesContext() {
        var context = TranslationContext(sourceLanguageName: "Japanese")
        context.gameTitle = "Test Quest"
        context.glossary = [GlossaryEntry(source: "Aria", target: "อาเรีย")]
        context.recentLines = [(original: "Hi", translation: "หวัดดี")]

        let prompt = LLMPrompt.system(batch: true, context: context)
        XCTAssertTrue(prompt.contains("Japanese-to-Thai"))
        XCTAssertTrue(prompt.contains("\"Test Quest\""))
        XCTAssertTrue(prompt.contains("Aria => อาเรีย"))
        XCTAssertTrue(prompt.contains("Hi => หวัดดี"))
        XCTAssertTrue(prompt.contains("[N] numbering"))
    }

    func testSystemPromptOmitsEmptySections() {
        let prompt = LLMPrompt.system(batch: false, context: TranslationContext(sourceLanguageName: "English"))
        XCTAssertFalse(prompt.contains("Glossary"))
        XCTAssertFalse(prompt.contains("for context only"))
        XCTAssertFalse(prompt.contains("The game is"))
    }

    func testBasicContextMapsLanguageCode() {
        XCTAssertEqual(TranslationContext.basic(from: "ja").sourceLanguageName, "Japanese")
        XCTAssertEqual(TranslationContext.basic(from: "zh-TW").sourceLanguageName, "Traditional Chinese")
        XCTAssertEqual(TranslationContext.basic(from: "xx").sourceLanguageName, "xx")
    }
}
