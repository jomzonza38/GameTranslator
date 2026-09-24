import XCTest
@testable import GameTranslator

private final class CountingLLM: LLMChatProvider, @unchecked Sendable {
    let name = "Counting"
    let limitDescription = ""
    let requiresApiKey = false
    private let lock = NSLock()
    private var count = 0
    private(set) var lastUser = ""
    var calls: Int { lock.withLock { count } }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        lock.withLock { count += 1; lastUser = user }
        return "คำตอบภาษาไทย"
    }
}

final class ChatPromptTests: XCTestCase {
    private let context = ChatItemContext(
        original: "Take the Holy Sword to the Bishop",
        translation: "นำดาบศักดิ์สิทธิ์ไปให้บิชอป",
        gameTitle: "Graveyard Keeper",
        sourceLanguage: "English",
        glossary: [
            GlossaryEntry(source: "Bishop", target: "บิชอป"),
            GlossaryEntry(source: "Graveyard", target: "สุสาน"),
        ]
    )

    // AC-1

    func testPromptHasOriginalTranslationGameAndOnlyRelevantGlossary() {
        let system = ChatPrompt.system(context)
        let user = ChatPrompt.user(context: context, history: [], question: "ทำไมแปลแบบนี้?")
        XCTAssertTrue(system.contains("Graveyard Keeper"))
        XCTAssertTrue(user.contains("Take the Holy Sword to the Bishop"))
        XCTAssertTrue(user.contains("นำดาบศักดิ์สิทธิ์ไปให้บิชอป"))
        XCTAssertTrue(user.contains("Bishop = บิชอป"))
        XCTAssertFalse(user.contains("สุสาน"), "glossary term not in the line")
        XCTAssertTrue(user.hasSuffix("Student's question: ทำไมแปลแบบนี้?"))
    }

    func testHistoryIsTrimmedToTheLastTurnsWithoutNotices() {
        var history: [ChatTurn] = []
        for i in 0..<14 {
            history.append(ChatTurn(role: i % 2 == 0 ? .user : .assistant, text: "turn \(i)"))
        }
        history.append(ChatTurn(role: .notice, text: "หยุดแล้ว"))
        let trimmed = ChatPrompt.trimmedHistory(history)
        XCTAssertEqual(trimmed.count, ChatPrompt.maxHistoryTurns)
        XCTAssertEqual(trimmed.first?.text, "turn 4")
        XCTAssertFalse(trimmed.contains { $0.role == .notice })

        let user = ChatPrompt.user(context: context, history: history, question: "ต่อ")
        XCTAssertFalse(user.contains("turn 3\\n"))
        XCTAssertTrue(user.contains("turn 13"))
        XCTAssertFalse(user.contains("หยุดแล้ว"))
    }

    // AC-2

    func testChatProviderDefaultAndPersistence() throws {
        let suite = "GameTranslatorTests.chat.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(AppSettings.loadLearningChatProvider(defaults, selectedProvider: .openAI), .openAI, "translation LLM")
        XCTAssertEqual(AppSettings.loadLearningChatProvider(defaults, selectedProvider: .googleFree), .claudeHaiku, "else Claude")

        defaults.set(AppSettings.TranslationProviderType.openAI.rawValue, forKey: AppSettings.learningChatProviderKey)
        XCTAssertEqual(AppSettings.loadLearningChatProvider(defaults, selectedProvider: .googleFree), .openAI, "stored choice")

        defaults.set(AppSettings.TranslationProviderType.deeplFree.rawValue, forKey: AppSettings.learningChatProviderKey)
        XCTAssertEqual(AppSettings.loadLearningChatProvider(defaults, selectedProvider: .googleFree), .claudeHaiku, "non-LLM ignored")
    }
}

@MainActor
final class LearningChatServiceTests: XCTestCase {
    private let context = ChatItemContext(original: "Open the gate", translation: "เปิดประตู", gameTitle: "G",
                                          sourceLanguage: "English", glossary: [])

    private func waitUntilIdle(_ service: LearningChatService) async {
        for _ in 0..<200 where service.isSending {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // AC-3

    func testNoKeyGivesThaiMessageWithoutARequest() {
        let llm = CountingLLM()
        let service = LearningChatService(provider: { .claudeHaiku }, keyFor: { _ in "" }, makeLLM: { _, _ in llm })
        let item = UUID()
        service.send("ทำไมแปลแบบนี้?", about: item, context: context)
        XCTAssertEqual(llm.calls, 0)
        XCTAssertFalse(service.isSending)
        XCTAssertEqual(service.turns(for: item).last?.role, .notice)
        XCTAssertTrue(service.turns(for: item).last?.text.contains("API key") == true)
    }

    func testAnswerIsKeptPerItemAndFollowUpIncludesHistory() async {
        let llm = CountingLLM()
        let service = LearningChatService(provider: { .openAI }, keyFor: { _ in "sk" }, makeLLM: { _, _ in llm })
        let item = UUID()
        service.send("ทำไมแปลแบบนี้?", about: item, context: context)
        await waitUntilIdle(service)
        XCTAssertEqual(service.turns(for: item).map(\.role), [.user, .assistant])

        service.send("ขอตัวอย่างอีก", about: item, context: context)
        await waitUntilIdle(service)
        XCTAssertEqual(llm.calls, 2)
        XCTAssertTrue(llm.lastUser.contains("Student: ทำไมแปลแบบนี้?"))
        XCTAssertTrue(llm.lastUser.contains("Teacher: คำตอบภาษาไทย"))

        XCTAssertTrue(service.turns(for: UUID()).isEmpty, "other items have their own chat")
        service.clear(item: item)
        XCTAssertTrue(service.turns(for: item).isEmpty)
    }

    func testSecondQuestionWhileWaitingIsIgnored() {
        let llm = CountingLLM()
        let service = LearningChatService(provider: { .openAI }, keyFor: { _ in "sk" }, makeLLM: { _, _ in llm })
        let item = UUID()
        service.send("หนึ่ง", about: item, context: context)
        service.send("สอง", about: item, context: context)
        XCTAssertEqual(service.turns(for: item).filter { $0.role == .user }.count, 1)
        service.stop()
        XCTAssertFalse(service.isSending)
    }
}
