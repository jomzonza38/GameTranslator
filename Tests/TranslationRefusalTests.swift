import XCTest
@testable import GameTranslator

final class TranslationRefusalTests: XCTestCase {
    func testKeyAndQuotaErrorsPause() {
        let pausing: [Error] = [
            TranslationError.translationFailed(message: "HTTP 401: invalid x-api-key"),
            TranslationError.translationFailed(message: "HTTP 403"),
            TranslationError.missingApiKey,
            TranslationError.quotaExceeded(provider: "DeepL Free", limit: "500,000"),
        ]
        for error in pausing {
            XCTAssertNotNil(TranslationRefusal.kind(of: error), "\(error)")
            XCTAssertNotNil(TranslationRefusal.pauseMessage(for: error, provider: "Claude Haiku", usesApiKey: true), "\(error)")
        }
    }

    func testRateLimitNetworkAndServerErrorsDoNotPause() {
        let notPausing: [Error] = [
            TranslationError.rateLimitExceeded,
            TranslationError.translationFailed(message: "HTTP 429: slow down"),
            TranslationError.translationFailed(message: "HTTP 500: server error"),
            TranslationError.translationFailed(message: "HTTP 503"),
            TranslationError.networkError(underlying: URLError(.timedOut)),
            TranslationError.networkError(underlying: URLError(.notConnectedToInternet)),
            TranslationError.invalidResponse,
            CancellationError(),
        ]
        for error in notPausing {
            XCTAssertNil(TranslationRefusal.kind(of: error), "\(error)")
            XCTAssertNil(TranslationRefusal.pauseMessage(for: error, provider: "Claude Haiku", usesApiKey: true), "\(error)")
        }
    }

    func testMessagesNameTheProviderAndTheFix() {
        let key = TranslationRefusal.pauseMessage(
            for: TranslationError.translationFailed(message: "HTTP 401"), provider: "Claude Haiku", usesApiKey: true
        )
        XCTAssertEqual(key, "หยุดแปลชั่วคราว: Claude Haiku ไม่รับ API Key — แก้ Key ใน ⚙️ ตั้งค่า แล้วจะแปลต่อเอง")

        let quota = TranslationRefusal.pauseMessage(
            for: TranslationError.quotaExceeded(provider: "DeepL Free", limit: ""), provider: "DeepL Free", usesApiKey: true
        )
        XCTAssertEqual(quota, "หยุดแปลชั่วคราว: DeepL Free ใช้โควต้าหมดแล้ว — เปลี่ยน provider ใน ⚙️ ตั้งค่า แล้วจะแปลต่อเอง")

        // Google Free has no key: a 403 means it blocked the requests
        let blocked = TranslationRefusal.pauseMessage(
            for: TranslationError.translationFailed(message: "HTTP 403"), provider: "Google Translate (Free)", usesApiKey: false
        )
        XCTAssertEqual(blocked, "หยุดแปลชั่วคราว: Google Translate (Free) ปฏิเสธคำขอ — ลองเปลี่ยน provider ใน ⚙️ ตั้งค่า")
    }

    // MARK: T-0014 — refusals of an outdated key/provider

    private let refused = TranslationError.translationFailed(message: "HTTP 401: invalid x-api-key")

    func testRefusalOfCurrentKeyPauses() {
        XCTAssertEqual(
            TranslationRefusal.outcome(for: refused, provider: "Claude Haiku", usesApiKey: true,
                                       requestGeneration: 3, currentGeneration: 3),
            .pause(message: "หยุดแปลชั่วคราว: Claude Haiku ไม่รับ API Key — แก้ Key ใน ⚙️ ตั้งค่า แล้วจะแปลต่อเอง")
        )
    }

    func testRefusalSentBeforeUpdateProviderIsIgnored() {
        // Request sent with generation 3, then the key was saved (updateProvider → 4)
        XCTAssertEqual(
            TranslationRefusal.outcome(for: refused, provider: "Claude Haiku", usesApiKey: true,
                                       requestGeneration: 3, currentGeneration: 4),
            .ignoreOutdated
        )
        let quota = TranslationError.quotaExceeded(provider: "DeepL Free", limit: "")
        XCTAssertEqual(
            TranslationRefusal.outcome(for: quota, provider: "DeepL Free", usesApiKey: true,
                                       requestGeneration: 1, currentGeneration: 2),
            .ignoreOutdated
        )
    }

    func testOtherErrorsAreNotRefusalsWhateverTheGeneration() {
        for generation in [3, 4] {
            XCTAssertEqual(
                TranslationRefusal.outcome(for: TranslationError.rateLimitExceeded, provider: "Claude Haiku",
                                           usesApiKey: true, requestGeneration: 3, currentGeneration: generation),
                .notARefusal
            )
        }
    }

    func testPauseMessageNamesTheProviderThatRefused() {
        // Request went to OpenAI; the message must say OpenAI
        guard case .pause(let message) = TranslationRefusal.outcome(
            for: refused, provider: "OpenAI GPT-4o-mini", usesApiKey: true, requestGeneration: 7, currentGeneration: 7
        ) else { return XCTFail("expected pause") }
        XCTAssertTrue(message.contains("OpenAI GPT-4o-mini"))
    }
}
