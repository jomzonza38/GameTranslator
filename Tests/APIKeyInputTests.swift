import XCTest
@testable import GameTranslator

final class APIKeyInputTests: XCTestCase {
    func testPastedKeyIsTrimmed() {
        XCTAssertEqual(APIKeyInput.normalized("  sk-abc \n"), "sk-abc")
        XCTAssertEqual(APIKeyInput.normalized("\tsk-ant-123\r\n"), "sk-ant-123")
    }

    func testWhitespaceOnlyKeyCountsAsEmpty() {
        XCTAssertEqual(APIKeyInput.normalized("   \n"), "")
        XCTAssertTrue(APIKeyInput.normalized(" \t ").isEmpty)
    }

    func testValueToSaveIsTrimmedDraft() {
        XCTAssertEqual(APIKeyInput.valueToSave(draft: "sk-new \n", current: "sk-old"), "sk-new")
    }

    func testNothingToSaveWhenOnlyWhitespaceChanged() {
        XCTAssertNil(APIKeyInput.valueToSave(draft: " sk-abc ", current: "sk-abc"))
    }

    func testClearingTheKeySavesEmpty() {
        XCTAssertEqual(APIKeyInput.valueToSave(draft: "  ", current: "sk-abc"), "")
    }
}
