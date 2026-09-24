import XCTest
@testable import GameTranslator

/// LLM that answers from a closure and counts requests
private final class ScriptedLLM: LLMChatProvider, @unchecked Sendable {
    let name = "Scripted"
    let limitDescription = ""
    let requiresApiKey = false
    private let lock = NSLock()
    private var count = 0
    private(set) var lastUser = ""
    private(set) var lastSystem = ""
    private let respond: (String) throws -> String
    var calls: Int { lock.withLock { count } }

    init(respond: @escaping (String) throws -> String) { self.respond = respond }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        lock.withLock { count += 1; lastUser = user; lastSystem = system }
        return try respond(user)
    }
}

final class MeaningPromptTests: XCTestCase {
    // AC-1

    func testPromptHasWordExampleAndGameTitle() {
        let system = MeaningPrompt.system(gameTitle: "Graveyard Keeper", sourceLanguage: "English")
        let user = MeaningPrompt.user([.init(word: "sword", example: "Sharpen the sword")])
        XCTAssertTrue(system.contains("Graveyard Keeper"))
        XCTAssertTrue(user.contains("sword"))
        XCTAssertTrue(user.contains("Sharpen the sword"))
    }

    func testWellFormedReplyIsParsed() {
        let reply = "[1] noun | ดาบ | อาวุธของตัวละคร\n[2] verb | ลับ (ให้คม)"
        let parsed = MeaningPrompt.parse(reply, count: 2)
        XCTAssertEqual(parsed[1], .init(partOfSpeech: "Noun", meaning: "ดาบ", note: "อาวุธของตัวละคร"))
        XCTAssertEqual(parsed[2], .init(partOfSpeech: "Verb", meaning: "ลับ (ให้คม)", note: nil))
    }

    func testMalformedOrChatterReplyFillsNothing() {
        XCTAssertTrue(MeaningPrompt.parse("I'm sorry, could you please provide more context?", count: 2).isEmpty)
        XCTAssertTrue(MeaningPrompt.parse("[1] noun | sword | a weapon", count: 1).isEmpty, "no Thai meaning")
        XCTAssertTrue(MeaningPrompt.parse("[1] ดาบ", count: 1).isEmpty, "missing separator")
        XCTAssertTrue(MeaningPrompt.parse("[7] noun | ดาบ", count: 2).isEmpty, "number out of range")
        XCTAssertTrue(MeaningPrompt.parse("", count: 3).isEmpty)
    }

    // AC-2

    func testProviderChoiceOrder() {
        func choose(chat: AppSettings.TranslationProviderType?, selected: AppSettings.TranslationProviderType,
                    keys: Set<AppSettings.TranslationProviderType>) -> MeaningSource {
            MeaningSource.choose(chatProvider: chat, selectedProvider: selected, hasKey: { keys.contains($0) })
        }
        XCTAssertEqual(choose(chat: .openAI, selected: .claudeHaiku, keys: [.openAI, .claudeHaiku]), .llm(.openAI), "chat setting first")
        XCTAssertEqual(choose(chat: .openAI, selected: .claudeHaiku, keys: [.claudeHaiku]), .llm(.claudeHaiku), "chat LLM without key → selected")
        XCTAssertEqual(choose(chat: nil, selected: .googleFree, keys: [.openAI]), .llm(.openAI), "any LLM with a key")
        XCTAssertEqual(choose(chat: nil, selected: .deeplFree, keys: []), .googleFree)
    }
}

@MainActor
final class MeaningServiceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MeaningServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitUntilIdle(_ service: MeaningService) async {
        for _ in 0..<200 where service.isWorking {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // AC-3

    func testMeaningIsSavedAndNotRequestedAgainUnlessForced() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.addWords([.init(text: "sword", partOfSpeech: "Noun")], from: "Sharpen the sword", game: "G")
        let id = try XCTUnwrap(store.data(for: "G").words.first?.id)

        let llm = ScriptedLLM { _ in "[1] noun | ดาบ | อาวุธ" }
        let service = MeaningService(store: store, keyFor: { $0 == .claudeHaiku ? "sk-test" : "" },
                                     makeLLM: { _, _ in llm }, google: GoogleFreeProvider(),
                                     chatProvider: { nil }, selectedProvider: { .claudeHaiku })

        service.lookUp(wordIDs: [id], game: "G")
        await waitUntilIdle(service)
        XCTAssertEqual(store.data(for: "G").words.first?.meaning, "ดาบ")
        XCTAssertEqual(store.data(for: "G").words.first?.meaningSource, "ai")
        XCTAssertEqual(llm.calls, 1)
        XCTAssertTrue(llm.lastSystem.contains("\"G\""), "game title in the prompt")

        service.lookUp(wordIDs: [id], game: "G")
        await waitUntilIdle(service)
        XCTAssertEqual(llm.calls, 1, "already has a meaning → no request")

        service.lookUp(wordIDs: [id], game: "G", force: true)
        await waitUntilIdle(service)
        XCTAssertEqual(llm.calls, 2, "หาความหมายใหม่ sends one")
    }

    func testChatterLeavesTheWordWithoutMeaningAndShowsAMessage() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.addWords([.init(text: "sword", partOfSpeech: nil)], from: "Sharpen the sword", game: "G")
        let id = try XCTUnwrap(store.data(for: "G").words.first?.id)
        let llm = ScriptedLLM { _ in "I'm sorry, I need more context." }
        let service = MeaningService(store: store, keyFor: { _ in "sk" }, makeLLM: { _, _ in llm },
                                     chatProvider: { nil }, selectedProvider: { .openAI })
        service.lookUp(wordIDs: [id], game: "G")
        await waitUntilIdle(service)
        XCTAssertNil(store.data(for: "G").words.first?.meaning)
        XCTAssertNotNil(service.lastError)
    }

    func testFailureShowsThaiMessageAndIsNotRetried() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.addWords([.init(text: "sword", partOfSpeech: nil)], from: "Sharpen the sword", game: "G")
        let id = try XCTUnwrap(store.data(for: "G").words.first?.id)
        let llm = ScriptedLLM { _ in throw TranslationError.translationFailed(message: "HTTP 401") }
        let service = MeaningService(store: store, keyFor: { _ in "sk" }, makeLLM: { _, _ in llm },
                                     chatProvider: { nil }, selectedProvider: { .claudeHaiku })
        service.lookUp(wordIDs: [id], game: "G")
        await waitUntilIdle(service)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(llm.calls, 1)
        XCTAssertTrue(service.lastError?.hasPrefix("หาความหมายไม่สำเร็จ") == true)
    }

    func testExplainWithoutAnLLMKeyAsksForAKeyAndSendsNothing() throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "G", languageCode: "en")
        let id = try XCTUnwrap(store.data(for: "G").sentences.first?.id)
        let llm = ScriptedLLM { _ in "อธิบาย" }
        let service = MeaningService(store: store, keyFor: { _ in "" }, makeLLM: { _, _ in llm },
                                     chatProvider: { nil }, selectedProvider: { .googleFree })
        service.explain(sentenceID: id, game: "G")
        XCTAssertEqual(llm.calls, 0)
        XCTAssertTrue(service.lastError?.contains("API key") == true)
    }
}
