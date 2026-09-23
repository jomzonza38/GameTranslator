import XCTest
@testable import GameTranslator

final class GoogleFreeProviderTests: XCTestCase {
    func testQueryEscapeEncodesReservedCharacters() {
        let escaped = GoogleFreeProvider.queryEscape("Salt & Pepper + 1=2?/#")
        XCTAssertFalse(escaped.contains("&"))
        XCTAssertFalse(escaped.contains("+"))
        XCTAssertFalse(escaped.contains("="))
        XCTAssertFalse(escaped.contains("#"))
        XCTAssertEqual(escaped.removingPercentEncoding, "Salt & Pepper + 1=2?/#")
    }

    func testQueryEscapeKeepsNonASCIIRoundTrip() {
        let source = "こんにちは\nWorld"
        XCTAssertEqual(GoogleFreeProvider.queryEscape(source).removingPercentEncoding, source)
    }

    func testSplitBatchMatchingLineCount() {
        XCTAssertEqual(GoogleFreeProvider.splitBatch("หนึ่ง\n สอง \nสาม", count: 3), ["หนึ่ง", "สอง", "สาม"])
    }

    func testSplitBatchRejectsExtraLines() {
        // Google split the first line in two — must not shift the rest
        XCTAssertNil(GoogleFreeProvider.splitBatch("a1\na2\nb\nc", count: 3))
    }

    func testSplitBatchRejectsMissingLines() {
        XCTAssertNil(GoogleFreeProvider.splitBatch("ab\nc", count: 3))
    }
}
