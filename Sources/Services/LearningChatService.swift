import Foundation

/// One message in a Learning-window chat (T-0025)
struct ChatTurn: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
        /// Thai error / status shown in the chat, never sent to the AI
        case notice
    }

    let id = UUID()
    let role: Role
    let text: String
}

/// What the chat is about
struct ChatItemContext: Equatable {
    let original: String
    /// The game's Thai translation (for a word: its meaning, if any)
    let translation: String?
    let gameTitle: String
    let sourceLanguage: String
    /// The game's glossary (only terms that appear in `original` are sent)
    let glossary: [GlossaryEntry]
}

/// Prompt building for the chat. Multi-turn is done by sending the recent turns inside
/// the user message, so the providers and the translation prompt path stay unchanged.
enum ChatPrompt {
    static let maxHistoryTurns = 10

    static let quickQuestions = [
        "ทำไมแปลแบบนี้?",
        "แยกคำศัพท์ในประโยคนี้",
        "แปลแบบอื่นได้ไหม?",
        "ยกตัวอย่างประโยคอื่น",
    ]

    static func system(_ context: ChatItemContext) -> String {
        """
        You are a friendly language teacher helping a Thai player learn \(context.sourceLanguage) from the game "\(context.gameTitle)".
        Answer in Thai, clearly and briefly, like a patient teacher. Use the game line and its Thai translation below as the topic.
        If the game's Thai translation is wrong or could be better, say so and suggest a better one.
        """
    }

    /// Glossary entries whose source term appears in the text (case-insensitive)
    static func relevantGlossary(_ glossary: [GlossaryEntry], in text: String) -> [GlossaryEntry] {
        glossary.filter { $0.isUsable && text.localizedCaseInsensitiveContains($0.source.trimmingCharacters(in: .whitespaces)) }
    }

    static func user(context: ChatItemContext, history: [ChatTurn], question: String) -> String {
        var lines = ["Game line: \(context.original)"]
        if let translation = context.translation, !translation.isEmpty {
            lines.append("Thai translation shown in the game: \(translation)")
        }
        let glossary = relevantGlossary(context.glossary, in: context.original)
        if !glossary.isEmpty {
            lines.append("Game glossary terms in this line: " + glossary.map { "\($0.source) = \($0.target)" }.joined(separator: "; "))
        }
        let recent = trimmedHistory(history)
        if !recent.isEmpty {
            lines.append("")
            lines.append("Conversation so far:")
            for turn in recent {
                lines.append("\(turn.role == .user ? "Student" : "Teacher"): \(turn.text)")
            }
        }
        lines.append("")
        lines.append("Student's question: \(question)")
        return lines.joined(separator: "\n")
    }

    /// The last `maxHistoryTurns` user/assistant turns (notices are not sent)
    static func trimmedHistory(_ history: [ChatTurn], maxTurns: Int = maxHistoryTurns) -> [ChatTurn] {
        Array(history.filter { $0.role != .notice }.suffix(maxTurns))
    }
}

/// Chats about Learning-window items, one per item for the session (T-0025). Requests
/// are only sent when the user presses send or a quick question; the provider key is
/// read at that moment. Never touches the translation pipeline.
@MainActor
final class LearningChatService: ObservableObject {
    static let shared = LearningChatService()

    /// Chats by item id (sentence or word), kept for the session
    @Published private(set) var chats: [UUID: [ChatTurn]] = [:]
    /// The item whose question is being answered (nil = idle)
    @Published private(set) var sendingItem: UUID?

    private let provider: () -> AppSettings.TranslationProviderType
    private let keyFor: (AppSettings.TranslationProviderType) -> String
    private let makeLLM: (AppSettings.TranslationProviderType, String) -> LLMChatProvider
    private var task: Task<Void, Never>?

    init(
        provider: (() -> AppSettings.TranslationProviderType)? = nil,
        keyFor: ((AppSettings.TranslationProviderType) -> String)? = nil,
        makeLLM: ((AppSettings.TranslationProviderType, String) -> LLMChatProvider)? = nil
    ) {
        self.provider = provider ?? { AppSettings.shared.learningChatProvider }
        self.keyFor = keyFor ?? { type in
            let settings = AppSettings.shared
            settings.loadApiKeyIfNeeded(for: type)
            return type == .openAI ? settings.openAIApiKey : settings.claudeApiKey
        }
        self.makeLLM = makeLLM ?? { type, key -> LLMChatProvider in
            if type == .openAI { return OpenAIProvider(apiKey: key) }
            return ClaudeProvider(apiKey: key)
        }
    }

    var isSending: Bool { sendingItem != nil }

    func turns(for item: UUID) -> [ChatTurn] {
        chats[item] ?? []
    }

    /// Ask `question` about the item. Ignored while another answer is loading.
    func send(_ question: String, about item: UUID, context: ChatItemContext) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, sendingItem == nil else { return }

        let type = provider()
        let key = keyFor(type)
        let history = turns(for: item)
        append(ChatTurn(role: .user, text: text), to: item)
        guard !key.isEmpty else {
            append(ChatTurn(role: .notice, text: "ยังไม่มี API key ของ \(type.displayName) — ใส่ API key ได้ที่ ตั้งค่า → AI สำหรับแชทเรียนรู้"), to: item)
            return
        }

        sendingItem = item
        let llm = makeLLM(type, key)
        let system = ChatPrompt.system(context)
        let user = ChatPrompt.user(context: context, history: history, question: text)
        GameLog.log("Learning chat: request via \(type.displayName) (\(user.count) chars)")
        task = Task { [weak self] in
            do {
                let reply = try await llm.complete(system: system, user: user, maxTokens: 900)
                guard let self, !Task.isCancelled else { return }
                let answer = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                self.append(ChatTurn(role: answer.isEmpty ? .notice : .assistant,
                                     text: answer.isEmpty ? "AI ไม่ได้ตอบ — ลองถามใหม่อีกครั้ง" : answer), to: item)
                GameLog.log("Learning chat: answer (\(answer.count) chars)")
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.append(ChatTurn(role: .notice, text: "ถามไม่สำเร็จ: \(error.localizedDescription)"), to: item)
                GameLog.log("Learning chat: request failed")
            }
            self?.sendingItem = nil
        }
    }

    /// Stop waiting for the current answer
    func stop() {
        task?.cancel()
        task = nil
        if let item = sendingItem {
            append(ChatTurn(role: .notice, text: "หยุดแล้ว"), to: item)
        }
        sendingItem = nil
    }

    /// "ล้างแชท"
    func clear(item: UUID) {
        if sendingItem == item { stop() }
        chats[item] = nil
    }

    private func append(_ turn: ChatTurn, to item: UUID) {
        chats[item, default: []].append(turn)
    }
}
