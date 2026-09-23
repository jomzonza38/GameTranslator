import Foundation

/// Anthropic Claude Haiku translation provider
/// Produces natural, human-sounding Thai translations using Claude API
final class ClaudeProvider: LLMChatProvider {
    let name = "Claude Haiku"
    let limitDescription = "$1 input / $5 output ต่อ 1M tokens (ต้องใช้ API Key)"
    let requiresApiKey = true

    private let apiKey: String
    private let session: URLSession
    private let model: String

    init(apiKey: String, model: String = "claude-haiku-4-5-20251001") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpMaximumConnectionsPerHost = 4
        self.session = URLSession(configuration: config)
    }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        guard !apiKey.isEmpty else { throw TranslationError.missingApiKey }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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
                  let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let text = first["text"] as? String else {
                throw TranslationError.invalidResponse
            }

            // Track token usage
            if let usage = json["usage"] as? [String: Any] {
                let inputTokens = (usage["input_tokens"] as? Int) ?? 0
                let outputTokens = (usage["output_tokens"] as? Int) ?? 0
                await MainActor.run {
                    AppSettings.shared.addCharacterUsage(inputTokens + outputTokens)
                }
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }
}
