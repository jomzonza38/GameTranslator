import XCTest
@testable import GameTranslator

// MARK: - Fakes

/// Chat provider whose replies come from a closure; counts `complete` calls
private final class FakeLLMProvider: LLMChatProvider, @unchecked Sendable {
    let name = "Fake LLM"
    let limitDescription = ""
    let requiresApiKey = false

    private let lock = NSLock()
    private var callCount = 0
    private let respond: (String) throws -> String

    var calls: Int { lock.withLock { callCount } }

    init(respond: @escaping (String) throws -> String) {
        self.respond = respond
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        lock.withLock { callCount += 1 }
        return try respond(user)
    }
}

/// Answers every request of a URLSession with `handler(q)` and counts requests.
/// `q` is the decoded text Google Free sends.
private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((String) -> (status: Int, body: String))?
    nonisolated(unsafe) private static var count = 0

    static var requestCount: Int { lock.withLock { count } }

    static func reset(_ newHandler: @escaping (String) -> (status: Int, body: String)) {
        lock.withLock {
            handler = newHandler
            count = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let q = request.url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?
            .first { $0.name == "q" }?.value ?? ""
        let handler = Self.lock.withLock { () -> ((String) -> (status: Int, body: String))? in
            Self.count += 1
            return Self.handler
        }
        let (status, body) = handler?(q) ?? (500, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Google Free JSON for one translated string: [[["<text>","<source>",null,null,1]],null,"en"]
private func googleJSON(_ text: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [[[text, "src", NSNull(), NSNull(), 1]], NSNull(), "en"])
    return String(data: data, encoding: .utf8)!
}

// MARK: - Tests

final class BatchFallbackTests: XCTestCase {
    private let texts = ["one", "two", "three"]

    // MARK: LLM providers

    private func assertBatchThrowsWithoutFallback(_ error: Error, file: StaticString = #filePath, line: UInt = #line) async {
        let provider = FakeLLMProvider { _ in throw error }
        do {
            _ = try await provider.translateBatch(texts, from: "en", to: "th")
            XCTFail("expected an error", file: file, line: line)
        } catch {
            // expected
        }
        XCTAssertEqual(provider.calls, 1, "no per-line requests after \(error)", file: file, line: line)
    }

    func testLLMRateLimitIsRethrownWithoutPerLineRequests() async {
        let provider = FakeLLMProvider { _ in throw TranslationError.rateLimitExceeded }
        do {
            _ = try await provider.translateBatch(texts, from: "en", to: "th")
            XCTFail("expected rateLimitExceeded")
        } catch TranslationError.rateLimitExceeded {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(provider.calls, 1)
    }

    func testLLMMissingApiKeyIsRethrownWithoutPerLineRequests() async {
        let provider = FakeLLMProvider { _ in throw TranslationError.missingApiKey }
        do {
            _ = try await provider.translateBatch(texts, from: "en", to: "th")
            XCTFail("expected missingApiKey")
        } catch TranslationError.missingApiKey {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(provider.calls, 1)
    }

    func testLLMCancellationIsRethrownWithoutPerLineRequests() async {
        let provider = FakeLLMProvider { _ in throw CancellationError() }
        do {
            _ = try await provider.translateBatch(texts, from: "en", to: "th")
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(provider.calls, 1)
    }

    func testLLMHTTP401IsRethrownWithoutPerLineRequests() async {
        await assertBatchThrowsWithoutFallback(TranslationError.translationFailed(message: "HTTP 401: invalid x-api-key"))
    }

    func testLLMMissingNumberedLineFallsBackToPerLine() async throws {
        let provider = FakeLLMProvider { user in
            // Batch request: reply is missing line [3]
            if user.hasPrefix("[1]") { return "[1] หนึ่ง\n[2] สอง" }
            return "แปล \(user)"
        }
        let result = try await provider.translateBatch(texts, from: "en", to: "th")
        XCTAssertEqual(result, ["แปล one", "แปล two", "แปล three"])
        XCTAssertEqual(provider.calls, 4, "1 batch + 3 per-line")
    }

    // MARK: Google Free

    private func makeGoogle() -> GoogleFreeProvider {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return GoogleFreeProvider(configuration: config)
    }

    func testGoogleRateLimitIsRethrownWithoutParallelRequests() async {
        StubURLProtocol.reset { _ in (429, "") }
        do {
            _ = try await makeGoogle().translateBatch(texts, from: "en", to: "th")
            XCTFail("expected rateLimitExceeded")
        } catch TranslationError.rateLimitExceeded {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testGoogleBlockedIsRethrownWithoutParallelRequests() async {
        StubURLProtocol.reset { _ in (403, "") }
        do {
            _ = try await makeGoogle().translateBatch(texts, from: "en", to: "th")
            XCTFail("expected an error")
        } catch {
            // expected: "HTTP 403"
        }
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    func testGoogleSplitMismatchFallsBackToParallel() async throws {
        StubURLProtocol.reset { q in
            // Batch (3 lines joined by \n) comes back as 2 lines; single lines work
            q.contains("\n") ? (200, googleJSON("ก\nข")) : (200, googleJSON("แปล \(q)"))
        }
        let result = try await makeGoogle().translateBatch(texts, from: "en", to: "th")
        XCTAssertEqual(result, ["แปล one", "แปล two", "แปล three"])
        XCTAssertEqual(StubURLProtocol.requestCount, 4, "1 batch + 3 parallel")
    }

    func testGoogleServerErrorStillFallsBackToParallel() async throws {
        StubURLProtocol.reset { q in
            q.contains("\n") ? (500, "") : (200, googleJSON("แปล \(q)"))
        }
        let result = try await makeGoogle().translateBatch(texts, from: "en", to: "th")
        XCTAssertEqual(result, ["แปล one", "แปล two", "แปล three"])
        XCTAssertEqual(StubURLProtocol.requestCount, 4)
    }

    // MARK: Decision rules

    func testNoPerLineRetryForRefusalsCancelAndOffline() {
        let noRetry: [Error] = [
            TranslationError.rateLimitExceeded,
            TranslationError.missingApiKey,
            TranslationError.quotaExceeded(provider: "DeepL", limit: "500K"),
            TranslationError.translationFailed(message: "HTTP 401: bad key"),
            TranslationError.translationFailed(message: "HTTP 403"),
            TranslationError.translationFailed(message: "HTTP 429: slow down"),
            CancellationError(),
            URLError(.cancelled),
            TranslationError.networkError(underlying: URLError(.cancelled)),
            TranslationError.networkError(underlying: URLError(.notConnectedToInternet)),
        ]
        for error in noRetry {
            XCTAssertFalse(BatchFallback.shouldRetryPerLine(after: error), "\(error)")
        }
    }

    func testPerLineRetryForTimeoutsServerErrorsAndBadReplies() {
        let retry: [Error] = [
            TranslationError.networkError(underlying: URLError(.timedOut)),
            TranslationError.translationFailed(message: "HTTP 500: server error"),
            TranslationError.invalidResponse,
        ]
        for error in retry {
            XCTAssertTrue(BatchFallback.shouldRetryPerLine(after: error), "\(error)")
        }
    }
}
