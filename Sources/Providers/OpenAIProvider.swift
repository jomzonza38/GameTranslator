import Foundation

/// OpenAI GPT-4o-mini translation provider
/// Produces natural, human-sounding Thai translations
final class OpenAIProvider: TranslationProvider {
    let name = "OpenAI GPT-4o-mini"
    let limitDescription = "~$0.15/1M tokens (ต้องใช้ API Key)"
    let requiresApiKey = true

    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.missingApiKey }

        let systemPrompt = """
            You are a game dialogue translator specializing in English-to-Thai localization. \
            Translate the text to Thai as it would appear in a published Thai game localization. \
            Rules: \
            1) Output ONLY the Thai translation, nothing else. \
            2) Match the dramatic/emotional tone of the original — if it's serious, keep it serious; if playful, keep it playful. \
            3) Use natural Thai phrasing that feels immersive and fitting for a game script. \
            4) Keep proper nouns, character names, and game terms in English. \
            5) Keep it concise — don't over-explain or pad the translation.
            """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (responseData, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw TranslationError.rateLimitExceeded
            }

            guard httpResponse.statusCode == 200 else {
                let errorMsg = String(data: responseData, encoding: .utf8) ?? "Unknown"
                throw TranslationError.translationFailed(message: "HTTP \(httpResponse.statusCode): \(errorMsg.prefix(200))")
            }

            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw TranslationError.invalidResponse
            }

            let result = content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Track token usage
            if let usage = json["usage"] as? [String: Any],
               let totalTokens = usage["total_tokens"] as? Int {
                await MainActor.run {
                    AppSettings.shared.addCharacterUsage(totalTokens)
                }
            }

            return result
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        if texts.count == 1 { return [try await translate(texts[0], from: from, to: to)] }
        guard !apiKey.isEmpty else { throw TranslationError.missingApiKey }

        let systemPrompt = """
            You are a game dialogue translator specializing in English-to-Thai localization. \
            Translate each numbered line to Thai as it would appear in a published Thai game localization. \
            Rules: \
            1) Output ONLY the Thai translations, one per line, keeping the [N] numbering. \
            2) Match the dramatic/emotional tone — serious dialogue stays serious, humor stays humorous. \
            3) Use natural Thai that feels immersive and fitting for a game script. \
            4) Keep character names, proper nouns, and game terms in English. \
            5) Keep it concise — match the original's brevity.
            """

        // Number each text for reliable splitting
        let numbered = texts.enumerated().map { "[\($0.offset + 1)] \($0.element)" }
        let combined = numbered.joined(separator: "\n")

        // If combined text is too long, fall back to parallel
        if combined.count > 4000 {
            return try await translateParallel(texts, from: from, to: to)
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": combined]
            ],
            "temperature": 0.3,
            "max_tokens": 2000
        ]

        let data = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (responseData, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return try await translateParallel(texts, from: from, to: to)
            }

            guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return try await translateParallel(texts, from: from, to: to)
            }

            // Parse numbered results: [1] translation1\n[2] translation2...
            var resultMap: [Int: String] = [:]
            let lines = content.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for line in lines {
                // Match [N] prefix and extract the number and text
                if let match = line.range(of: #"^\[(\d+)\]\s*"#, options: .regularExpression) {
                    let numStr = line[match].filter(\.isNumber)
                    if let num = Int(numStr) {
                        let translated = String(line[match.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !translated.isEmpty {
                            resultMap[num] = translated
                        }
                    }
                }
            }

            // Build ordered results
            if resultMap.count == texts.count {
                let results = (1...texts.count).map { resultMap[$0] ?? "" }
                if !results.contains("") {
                    // Track token usage
                    if let usage = json["usage"] as? [String: Any],
                       let totalTokens = usage["total_tokens"] as? Int {
                        await MainActor.run {
                            AppSettings.shared.addCharacterUsage(totalTokens)
                        }
                    }
                    return results
                }
            }

            // Count mismatch — fall back to parallel
            return try await translateParallel(texts, from: from, to: to)
        } catch {
            return try await translateParallel(texts, from: from, to: to)
        }
    }

    private func translateParallel(_ texts: [String], from: String, to: String) async throws -> [String] {
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    let result = try await self.translate(text, from: from, to: to)
                    return (index, result)
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
