import XCTest
@testable import GameTranslator

/// Machine-translation style provider: returns "<name>:<text>" and counts requests
private final class CountingProvider: TranslationProvider, @unchecked Sendable {
    let name: String
    let limitDescription = ""
    let requiresApiKey = false

    private let lock = NSLock()
    private var requestCount = 0
    var requests: Int { lock.withLock { requestCount } }

    init(name: String) { self.name = name }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        "\(name):\(text)"
    }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        lock.withLock { requestCount += 1 }
        return texts.map { "\(name):\($0)" }
    }
}

/// Chat provider whose reply comes from a closure; counts `complete` calls
private final class ScriptedLLMProvider: LLMChatProvider, @unchecked Sendable {
    let name = "Scripted LLM"
    let limitDescription = ""
    let requiresApiKey = false

    private let lock = NSLock()
    private var callCount = 0
    private let respond: (String) -> String
    var calls: Int { lock.withLock { callCount } }

    init(respond: @escaping (String) -> String) { self.respond = respond }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        lock.withLock { callCount += 1 }
        return respond(user)
    }
}

final class TranslationServiceCacheTests: XCTestCase {
    private let chatter = "I'm sorry, could you please provide more context so I can translate this properly?"

    private func translate(
        _ texts: [String], with provider: TranslationProvider, cache: TranslationCache, sourceLanguage: String = "en"
    ) async throws -> [String: String] {
        try await TranslationService.translateBatch(
            texts, with: provider, cache: cache,
            sourceLanguage: sourceLanguage, targetLanguage: "th",
            context: TranslationContext(sourceLanguageName: "English")
        )
    }

    // AC-1

    func testCacheOfOneProviderIsNotUsedForAnother() async throws {
        let cache = TranslationCache()
        let google = CountingProvider(name: "Google")
        let claude = CountingProvider(name: "Claude")

        let first = try await translate(["Hello"], with: google, cache: cache)
        XCTAssertEqual(first["Hello"], "Google:Hello")

        let second = try await translate(["Hello"], with: claude, cache: cache)
        XCTAssertEqual(second["Hello"], "Claude:Hello", "must not return Google's cached line")
        XCTAssertEqual(claude.requests, 1)
    }

    func testSameProviderUsesItsCache() async throws {
        let cache = TranslationCache()
        let google = CountingProvider(name: "Google")
        _ = try await translate(["Hello"], with: google, cache: cache)
        let again = try await translate(["Hello"], with: google, cache: cache)
        XCTAssertEqual(again["Hello"], "Google:Hello")
        XCTAssertEqual(google.requests, 1, "second call served from cache")
    }

    func testCacheIsPerSourceLanguage() async throws {
        let cache = TranslationCache()
        let google = CountingProvider(name: "Google")
        _ = try await translate(["OK"], with: google, cache: cache, sourceLanguage: "en")
        _ = try await translate(["OK"], with: google, cache: cache, sourceLanguage: "ja")
        XCTAssertEqual(google.requests, 2)
    }

    // AC-2

    func testChatterReplyIsNotCachedAndIsAskedAgain() async throws {
        let cache = TranslationCache()
        let llm = ScriptedLLMProvider { _ in self.chatter }

        let first = try await translate(["Hello"], with: llm, cache: cache)
        XCTAssertNil(first["Hello"], "chatter is not a translation")

        let second = try await translate(["Hello"], with: llm, cache: cache)
        XCTAssertNil(second["Hello"])
        XCTAssertEqual(llm.calls, 2, "not served from cache — the provider was asked again")
    }

    func testChatterForOneLineOfABatchKeepsTheOthers() async throws {
        let cache = TranslationCache()
        let llm = ScriptedLLMProvider { _ in "[1] สวัสดี\n[2] \(self.chatter)" }

        let result = try await translate(["Hello", "Tell me more"], with: llm, cache: cache)
        XCTAssertEqual(result["Hello"], "สวัสดี")
        XCTAssertNil(result["Tell me more"])

        let cached = await cache.get(TranslationService.scope(provider: llm.name, sourceLanguage: "en") + "\nHello")
        XCTAssertEqual(cached, "สวัสดี")
    }

    func testLLMTranslateBatchStillShowsSourceForChatter() async throws {
        // Callers of the plain translateBatch keep the old behaviour (source text shown)
        let llm = ScriptedLLMProvider { _ in self.chatter }
        let result = try await llm.translateBatch(["Hello"], from: "en", to: "th")
        XCTAssertEqual(result, ["Hello"])
    }
}
