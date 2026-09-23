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

    func translateBatch(_ texts: [String], from: String, to: String, context: TranslationContext) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        if texts.count == 1 {
            return [try await translateOne(texts[0], context: context)]
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
                return results
            }
        } catch {
            // Fall through to per-line requests, which surface the real error if it persists
        }
        return try await translateEach(texts, context: context)
    }

    func translateOne(_ text: String, context: TranslationContext) async throws -> String {
        let reply = try await complete(
            system: LLMPrompt.system(batch: false, context: context),
            user: text,
            maxTokens: 500
        )
        return reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func translateEach(_ texts: [String], context: TranslationContext) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let translation = try await self.translateOne(text, context: context)
                    return (index, translation)
                }
            }
            var results = Array(repeating: "", count: texts.count)
            for try await (index, translation) in group {
                results[index] = translation
            }
            return results
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
        lines.append("4) Keep character names, proper nouns, and game terms in their original form unless the glossary below gives a Thai term.")
        lines.append("5) Keep it concise — match the original's brevity.")

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
