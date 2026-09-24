import Foundation

// MARK: - Provider choice

/// Where word meanings / explanations come from (T-0023)
enum MeaningSource: Equatable {
    /// An LLM (Claude / OpenAI) — meanings in the game's context
    case llm(AppSettings.TranslationProviderType)
    /// Google Translate Free — the word on its own, no context
    case googleFree

    static let llmProviders: [AppSettings.TranslationProviderType] = [.claudeHaiku, .openAI]

    /// The AI-chat setting's LLM if it has a key (T-0025), else the selected translation
    /// provider if it is an LLM with a key, else any LLM with a key, else Google Free.
    static func choose(
        chatProvider: AppSettings.TranslationProviderType?,
        selectedProvider: AppSettings.TranslationProviderType,
        hasKey: (AppSettings.TranslationProviderType) -> Bool
    ) -> MeaningSource {
        if let chatProvider, llmProviders.contains(chatProvider), hasKey(chatProvider) { return .llm(chatProvider) }
        if llmProviders.contains(selectedProvider), hasKey(selectedProvider) { return .llm(selectedProvider) }
        if let any = llmProviders.first(where: hasKey) { return .llm(any) }
        return .googleFree
    }
}

// MARK: - Prompts

/// Prompt text and reply parsing for word meanings and sentence explanations
enum MeaningPrompt {
    struct Request: Equatable {
        let word: String
        let example: String?
    }

    struct Meaning: Equatable {
        let partOfSpeech: String?
        let meaning: String
        let note: String?
    }

    static func system(gameTitle: String, sourceLanguage: String) -> String {
        """
        You are a friendly language teacher helping a Thai player learn \(sourceLanguage) from the game "\(gameTitle)".
        For each numbered word give its part of speech and its Thai meaning as it is used in the example line from this game.
        Reply ONLY with one line per word, in this exact format:
        [N] part of speech | Thai meaning | short Thai note (optional)
        Part of speech in English: noun, verb, adjective, adverb, or other. Keep the Thai meaning short (a few words).
        Never ask questions or add anything else.
        """
    }

    static func user(_ requests: [Request]) -> String {
        requests.enumerated().map { index, request in
            let example = request.example.map { " — example: \"\($0)\"" } ?? ""
            return "[\(index + 1)] \(request.word)\(example)"
        }
        .joined(separator: "\n")
    }

    /// Parse "[N] pos | meaning | note" lines. Lines that are malformed, chatter or have no
    /// Thai meaning are skipped — a word without a meaning is better than a wrong one.
    static func parse(_ reply: String, count: Int) -> [Int: Meaning] {
        var result: [Int: Meaning] = [:]
        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let match = line.range(of: #"^\[(\d+)\]\s*"#, options: .regularExpression),
                  let number = Int(line[match].filter(\.isNumber)),
                  (1...max(count, 1)).contains(number) else { continue }
            let parts = line[match.upperBound...]
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let meaning = parts[1]
            guard containsThai(meaning), !LLMPrompt.looksLikeChatter(meaning, source: "") else { continue }
            let note = parts.count >= 3 && !parts[2].isEmpty ? parts[2] : nil
            result[number] = Meaning(partOfSpeech: normalizedPartOfSpeech(parts[0]), meaning: meaning, note: note)
        }
        return result
    }

    static func explainSystem(gameTitle: String, sourceLanguage: String) -> String {
        """
        You are a friendly language teacher helping a Thai player learn \(sourceLanguage) from the game "\(gameTitle)".
        Explain the given game line in Thai, briefly (at most about 6 short lines): the key words, any grammar point,
        idiom or slang, and whether the game's Thai translation fits. Answer in Thai only.
        """
    }

    static func explainUser(original: String, translation: String) -> String {
        "Line: \(original)\nThai translation shown in the game: \(translation)"
    }

    /// NaturalLanguage tag name for an LLM's part of speech, if recognised
    static func normalizedPartOfSpeech(_ text: String) -> String? {
        switch text.lowercased() {
        case let s where s.hasPrefix("noun"): return "Noun"
        case let s where s.hasPrefix("verb"): return "Verb"
        case let s where s.hasPrefix("adj"): return "Adjective"
        case let s where s.hasPrefix("adv"): return "Adverb"
        case let s where s.hasPrefix("pron"): return "Pronoun"
        case let s where s.hasPrefix("interj"): return "Interjection"
        case let s where s.hasPrefix("prep"): return "Preposition"
        case let s where s.hasPrefix("conj"): return "Conjunction"
        default: return nil
        }
    }

    static func containsThai(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
    }
}

// MARK: - Service

/// Looks up word meanings and sentence explanations for the Learning window (T-0023).
/// Only ever started from that window — never from the translation pipeline, and it
/// doesn't use the translation cache. One batch at a time; failures are not retried.
@MainActor
final class MeaningService: ObservableObject {
    static let shared = MeaningService()

    /// Max words per request
    static let batchSize = 20

    @Published private(set) var isWorking = false
    /// Thai message for the last failure (nil = none)
    @Published private(set) var lastError: String?
    /// The last lookup used Google (no context) because no AI key exists
    @Published private(set) var lastUsedGoogle = false

    private let store: LearningStore
    /// Reads a provider's key (only when the user asks; not at launch)
    private let keyFor: (AppSettings.TranslationProviderType) -> String
    private let makeLLM: (AppSettings.TranslationProviderType, String) -> LLMChatProvider
    private let google: TranslationProvider
    private let chatProvider: () -> AppSettings.TranslationProviderType?
    private let selectedProvider: () -> AppSettings.TranslationProviderType
    private var task: Task<Void, Never>?

    init(
        store: LearningStore? = nil,
        keyFor: ((AppSettings.TranslationProviderType) -> String)? = nil,
        makeLLM: ((AppSettings.TranslationProviderType, String) -> LLMChatProvider)? = nil,
        google: TranslationProvider? = nil,
        chatProvider: (() -> AppSettings.TranslationProviderType?)? = nil,
        selectedProvider: (() -> AppSettings.TranslationProviderType)? = nil
    ) {
        self.store = store ?? .shared
        self.keyFor = keyFor ?? { type in
            let settings = AppSettings.shared
            settings.loadApiKeyIfNeeded(for: type)
            switch type {
            case .claudeHaiku: return settings.claudeApiKey
            case .openAI: return settings.openAIApiKey
            default: return ""
            }
        }
        self.makeLLM = makeLLM ?? { type, key -> LLMChatProvider in
            if type == .openAI { return OpenAIProvider(apiKey: key) }
            return ClaudeProvider(apiKey: key)
        }
        self.google = google ?? GoogleFreeProvider()
        self.chatProvider = chatProvider ?? { AppSettings.shared.learningChatProvider }
        self.selectedProvider = selectedProvider ?? { AppSettings.shared.selectedProvider }
    }

    /// Which source a lookup would use now
    func currentSource() -> MeaningSource {
        MeaningSource.choose(
            chatProvider: chatProvider(),
            selectedProvider: selectedProvider(),
            hasKey: { !keyFor($0).isEmpty }
        )
    }

    func cancel() {
        task?.cancel()
        task = nil
        isWorking = false
    }

    // MARK: Words

    /// Look up meanings for up to `batchSize` of `wordIDs` that have none (or all of them
    /// again with `force`). Runs one request; a failure shows a message and is not retried.
    func lookUp(wordIDs: [UUID], game: String, sourceLanguage: String, sourceCode: String, force: Bool = false) {
        guard !isWorking else { return }
        let data = store.data(for: game)
        let words = wordIDs.compactMap { id in data.words.first { $0.id == id } }
            .filter { force || $0.meaning == nil }
            .prefix(Self.batchSize)
        guard !words.isEmpty else { return }
        let batch = Array(words)

        isWorking = true
        lastError = nil
        let source = currentSource()
        lastUsedGoogle = source == .googleFree
        let key: String? = { if case .llm(let type) = source { return keyFor(type) } else { return nil } }()
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isWorking = false }
            do {
                let found = try await self.fetchMeanings(batch, source: source, key: key, game: game,
                                                         sourceLanguage: sourceLanguage, sourceCode: sourceCode)
                guard !Task.isCancelled else { return }
                self.store.mutate(game) { data in
                    for (id, meaning) in found {
                        guard let index = data.words.firstIndex(where: { $0.id == id }) else { continue }
                        data.words[index].meaning = meaning.meaning
                        data.words[index].meaningNote = meaning.note
                        data.words[index].meaningSource = source == .googleFree ? "google" : "ai"
                        if let pos = meaning.partOfSpeech { data.words[index].partOfSpeech = pos }
                    }
                }
                GameLog.log("Learning: meanings \(found.count)/\(batch.count) via \(source == .googleFree ? "Google Free" : "AI")")
                if found.isEmpty {
                    self.lastError = "ไม่ได้ความหมายจากคำตอบ — ลองใหม่อีกครั้ง"
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = "หาความหมายไม่สำเร็จ: \(error.localizedDescription)"
                GameLog.log("Learning: meaning lookup failed")
            }
        }
    }

    private func fetchMeanings(
        _ words: [LearningWord], source: MeaningSource, key: String?, game: String,
        sourceLanguage: String, sourceCode: String
    ) async throws -> [UUID: MeaningPrompt.Meaning] {
        switch source {
        case .llm(let type):
            let provider = makeLLM(type, key ?? "")
            let reply = try await provider.complete(
                system: MeaningPrompt.system(gameTitle: game, sourceLanguage: sourceLanguage),
                user: MeaningPrompt.user(words.map { .init(word: $0.word, example: $0.examples.last) }),
                maxTokens: 1500
            )
            let parsed = MeaningPrompt.parse(reply, count: words.count)
            var result: [UUID: MeaningPrompt.Meaning] = [:]
            for (index, word) in words.enumerated() {
                if let meaning = parsed[index + 1] { result[word.id] = meaning }
            }
            return result
        case .googleFree:
            let translations = try await google.translateBatch(words.map(\.word), from: sourceCode, to: "th")
            var result: [UUID: MeaningPrompt.Meaning] = [:]
            for (word, translation) in zip(words, translations) {
                let meaning = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !meaning.isEmpty, meaning.lowercased() != word.word else { continue }
                result[word.id] = .init(partOfSpeech: nil, meaning: meaning, note: nil)
            }
            return result
        }
    }

    // MARK: Sentences

    /// "อธิบายประโยคนี้": a short Thai explanation from the AI, saved with the sentence
    func explain(sentenceID: UUID, game: String, sourceLanguage: String, force: Bool = false) {
        guard !isWorking,
              let sentence = store.data(for: game).sentences.first(where: { $0.id == sentenceID }),
              force || sentence.explanation == nil else { return }
        guard case .llm(let type) = currentSource() else {
            lastError = "ต้องมี API key ของ Claude หรือ OpenAI (ตั้งค่า → Translation) จึงจะอธิบายประโยคได้"
            return
        }
        isWorking = true
        lastError = nil
        let provider = makeLLM(type, keyFor(type))
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isWorking = false }
            do {
                let reply = try await provider.complete(
                    system: MeaningPrompt.explainSystem(gameTitle: game, sourceLanguage: sourceLanguage),
                    user: MeaningPrompt.explainUser(original: sentence.original, translation: sentence.translation),
                    maxTokens: 600
                )
                guard !Task.isCancelled else { return }
                let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                guard MeaningPrompt.containsThai(text) else {
                    self.lastError = "คำตอบไม่ใช่คำอธิบายภาษาไทย — ลองใหม่อีกครั้ง"
                    return
                }
                self.store.mutate(game) { data in
                    if let index = data.sentences.firstIndex(where: { $0.id == sentenceID }) {
                        data.sentences[index].explanation = text
                    }
                }
                GameLog.log("Learning: sentence explained (\(text.count) chars)")
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = "อธิบายไม่สำเร็จ: \(error.localizedDescription)"
                GameLog.log("Learning: explanation failed")
            }
        }
    }
}
