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
}
