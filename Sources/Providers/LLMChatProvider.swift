import Foundation

/// A chat-model provider (OpenAI, Claude). Conformers only implement `complete`;
/// prompting, batching and parsing are shared in the extension below.
protocol LLMChatProvider: TranslationProvider {
    /// Send one system + user message and return the model's text reply
    func complete(system: String, user: String, maxTokens: Int) async throws -> String
}

extension LLMChatProvider {
    func translate(_ text: String, from: String, to: String) async throws -> String {
        try await translateOne(text, context: .basic(from: from))
    }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        try await translateBatch(texts, from: from, to: to, context: .basic(from: from))
    }

    /// Chatter replies fall back to the source text (shown as-is)
    func translateBatch(_ texts: [String], from: String, to: String, context: TranslationContext) async throws -> [String] {
        let results = try await translateBatchMarkingFallbacks(texts, from: from, to: to, context: context)
        return zip(results, texts).map { $0 ?? $1 }
    }

    /// `nil` for lines where the model answered with chatter instead of a translation
    func translateBatchMarkingFallbacks(_ texts: [String], from: String, to: String, context: TranslationContext) async throws -> [String?] {
        guard !texts.isEmpty else { return [] }
        if texts.count == 1 {
            return [try await translateOneMarkingFallback(texts[0], context: context)]
        }

        let combined = LLMPrompt.numbered(texts)

        // Very long batches are more likely to be mis-numbered — translate one by one
        if combined.count > 4000 {
            return try await translateEach(texts, context: context)
        }

        do {
            let reply = try await complete(
                system: LLMPrompt.system(batch: true, context: context),
                user: combined,
                maxTokens: 2000
            )
            if let results = LLMPrompt.parseNumbered(reply, count: texts.count) {
                return zip(results, texts).map { LLMPrompt.translation(fromReply: $0, source: $1) }
            }
            // Reply couldn't be matched to the lines — translate them one by one
        } catch {
            // Rate limit, bad key, quota, cancel, no network: every per-line request
            // would fail the same way, only N times over
            guard BatchFallback.shouldRetryPerLine(after: error) else { throw error }
        }
        return try await translateEach(texts, context: context)
    }

    func translateOne(_ text: String, context: TranslationContext) async throws -> String {
        try await translateOneMarkingFallback(text, context: context) ?? text
    }

    private func translateOneMarkingFallback(_ text: String, context: TranslationContext) async throws -> String? {
        let reply = try await complete(
            system: LLMPrompt.system(batch: false, context: context),
            user: text,
            maxTokens: 500
        )
        return LLMPrompt.translation(fromReply: reply, source: text)
    }

    private func translateEach(_ texts: [String], context: TranslationContext) async throws -> [String?] {
        try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let translation = try await self.translateOneMarkingFallback(text, context: context)
                    return (index, translation)
                }
            }
            var results = [String?](repeating: nil, count: texts.count)
            for try await (index, translation) in group {
                results[index] = translation
            }
            return results
        }
    }
}

/// When a failed batch request may be retried as one request per line (used by
/// LLMChatProvider and GoogleFreeProvider)
enum BatchFallback {
    /// True only when smaller requests can plausibly succeed. Not when the service
    /// refused us (rate limit, API key, quota), the task was cancelled (stop) or the
    /// network is down — then N parallel requests would all fail too, and against a
    /// rate limit they make things worse (and cost money with LLMs).
    /// Timeouts and other errors still fall back: a big batch can time out where
    /// single lines succeed.
    static func shouldRetryPerLine(after error: Error) -> Bool {
        if Task.isCancelled || error is CancellationError { return false }
        if let urlError = error as? URLError { return allowsRetry(urlError) }
        guard let translationError = error as? TranslationError else { return true }

        switch translationError {
        case .rateLimitExceeded, .missingApiKey, .quotaExceeded, .unsupportedLanguage:
            return false
        case .networkError(let underlying):
            if underlying is CancellationError { return false }
            if let urlError = underlying as? URLError { return allowsRetry(urlError) }
            return true
        case .translationFailed(let message):
            // Providers report HTTP errors as "HTTP <status>…": 401/403 = key refused or
            // blocked, 429 = rate limited
            return !["HTTP 401", "HTTP 403", "HTTP 429"].contains { message.hasPrefix($0) }
        case .invalidResponse:
            return true
        }
    }

    private static func allowsRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .cancelled, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .userAuthenticationRequired:
            return false
        default:
            return true
        }
    }
}

/// Prompt text and reply parsing shared by chat-model providers
enum LLMPrompt {
    static func system(batch: Bool, context: TranslationContext) -> String {
        let source = context.sourceLanguageName
        var lines: [String] = []

        lines.append("You are a game dialogue translator specializing in \(source)-to-Thai localization.")
        if !context.gameTitle.isEmpty {
            lines.append("The game is \"\(context.gameTitle)\". Use terminology and tone that fit this game.")
        }
        lines.append(batch
            ? "Translate each numbered line to Thai as it would appear in a published Thai game localization."
            : "Translate the text to Thai as it would appear in a published Thai game localization.")
        lines.append("Rules:")
        lines.append(batch
            ? "1) Output ONLY the Thai translations, one per line, keeping the [N] numbering."
            : "1) Output ONLY the Thai translation, nothing else.")
        lines.append("2) Match the dramatic/emotional tone — serious dialogue stays serious, humor stays humorous.")
        lines.append("3) Use natural Thai that feels immersive and fitting for a game script.")
        lines.append("4) Translate titles, epithets, roles, ranks and game terms into natural Thai the way an official Thai localization would (e.g. \"the Chosen One\" / \"Promised One\" → \"ผู้ถูกเลือก\", \"Guardian\" → \"ผู้พิทักษ์\"). Do not leave them in English and do not translate them word by word. Personal names of characters and places stay names — keep them as they are or write them in Thai script, consistently with previous lines. The glossary below always takes priority.")
        lines.append("5) Keep it concise — match the original's brevity.")
        lines.append("6) The input is raw on-screen game text captured by OCR. It may be a single word, a character name, a button label or a sentence fragment. Always output a translation — never ask questions, never ask for more context, never explain or add notes.")
        lines.append("7) If the text is a name or cannot be meaningfully translated, write it in Thai script or return it unchanged.")

        if !context.glossary.isEmpty {
            lines.append("")
            lines.append("Glossary — always translate these terms exactly as given:")
            for entry in context.glossary {
                lines.append("- \(entry.source) => \(entry.target)")
            }
        }

        if !context.recentLines.isEmpty {
            lines.append("")
            lines.append("Lines shown just before this, for context only. Do NOT translate or output them; use them to keep names, pronouns and tone consistent:")
            for line in context.recentLines {
                lines.append("- \(line.original) => \(line.translation)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Clean a model reply for one line. If the model answered with chatter instead of a
    /// translation (asking for context, apologizing, explaining), fall back to the source text.
    static func sanitize(_ reply: String, source: String) -> String {
        translation(fromReply: reply, source: source) ?? source
    }

    /// The cleaned translation in a model reply, or nil when the reply is empty or
    /// reads like chatter — then there is no translation to show or cache.
    static func translation(fromReply reply: String, source: String) -> String? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

        if let prefix = text.range(of: #"^\[\d+\]\s*"#, options: .regularExpression) {
            text.removeSubrange(prefix)
        }

        // Strip quotes wrapped around the whole reply
        let quotes: Set<Character> = ["\"", "“", "”", "'", "「", "」", "『", "』"]
        while text.count >= 2, let first = text.first, let last = text.last,
              quotes.contains(first), quotes.contains(last) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if text.isEmpty || looksLikeChatter(text, source: source) {
            return nil
        }
        return text
    }

    /// True when a reply reads like the model talking to the user rather than a translation
    static func looksLikeChatter(_ reply: String, source: String) -> Bool {
        let hasThai = reply.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }

        // Long reply without any Thai script — not a Thai translation
        if !hasThai && reply.count > source.count + 20 {
            return true
        }

        let lower = reply.lowercased()
        let sourceLower = source.lowercased()
        let markers = [
            "more context", "need more", "could you", "please provide", "provide the full",
            "not enough information", "isn't enough", "is not enough", "i'm sorry", "i am sorry",
            "i cannot", "i can't", "as an ai", "here is the translation", "here's the translation",
            "ต้องการบริบท", "ข้อมูลไม่เพียงพอ", "กรุณาให้ข้อมูล"
        ]
        let hasMarker = markers.contains { lower.contains($0) && !sourceLower.contains($0) }
        return hasMarker && reply.count > source.count * 2
    }

    /// "[1] first\n[2] second..."
    static func numbered(_ texts: [String]) -> String {
        texts.enumerated()
            .map { "[\($0.offset + 1)] \($0.element)" }
            .joined(separator: "\n")
    }

    /// Parse a "[N] translation" reply. Returns nil unless every line 1...count is present.
    static func parseNumbered(_ reply: String, count: Int) -> [String]? {
        var resultMap: [Int: String] = [:]
        let lines = reply.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            guard let match = line.range(of: #"^\[(\d+)\]\s*"#, options: .regularExpression) else { continue }
            let numberString = line[match].filter(\.isNumber)
            guard let number = Int(numberString) else { continue }
            let translated = String(line[match.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !translated.isEmpty {
                resultMap[number] = translated
            }
        }

        guard count > 0, resultMap.count >= count else { return nil }
        let results = (1...count).map { resultMap[$0] ?? "" }
        return results.contains("") ? nil : results
    }
}
