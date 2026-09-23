import Foundation

/// Google Translate (Free/Unofficial) provider
/// Uses the public translate API endpoint — no API key needed
/// Warning: may be rate-limited or blocked with heavy usage
final class GoogleFreeProvider: TranslationProvider {
    let name = "Google Translate (Free)"
    let limitDescription = "ไม่จำกัดอย่างเป็นทางการ (อาจถูก rate limit ถ้าใช้เยอะ)"
    let requiresApiKey = false

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        // Allow more concurrent connections for parallel fallback
        config.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: config)
    }

    func warmUp() {
        var request = URLRequest(url: URL(string: "https://translate.googleapis.com/")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        session.dataTask(with: request).resume()
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        let encodedText = Self.queryEscape(text)

        let urlString = "https://translate.googleapis.com/translate_a/single"
            + "?client=gtx"
            + "&sl=\(from)"
            + "&tl=\(to)"
            + "&hl=\(to)"   // Hint: target audience language for better phrasing
            + "&dt=t"
            + "&q=\(encodedText)"

        guard let url = URL(string: urlString) else {
            throw TranslationError.translationFailed(message: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }

            if httpResponse.statusCode == 429 {
                throw TranslationError.rateLimitExceeded
            }

            guard httpResponse.statusCode == 200 else {
                throw TranslationError.translationFailed(
                    message: "HTTP \(httpResponse.statusCode)"
                )
            }

            // Response format: [[["translated","original","","",0],...],null,"en",...]
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let sentences = jsonArray.first as? [[Any]] else {
                throw TranslationError.invalidResponse
            }

            let translated = sentences.compactMap { sentence -> String? in
                guard let text = sentence.first as? String else { return nil }
                return text
            }.joined()

            if translated.isEmpty {
                throw TranslationError.invalidResponse
            }

            await MainActor.run {
                AppSettings.shared.addCharacterUsage(text.count)
            }

            return translated
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }

    /// Percent-encode a query value. `.urlQueryAllowed` leaves `&`, `=` and `+`
    /// unescaped, so "Salt & Pepper" would be cut at the `&` and `+` read as a space.
    static func queryEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?/#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Batch translation: send all texts in ONE API call for speed AND better quality.
    ///
    /// Google Translate produces more natural Thai when it sees surrounding context
    /// (e.g. related game UI strings together). One HTTP request is also faster than
    /// N parallel requests when there are many texts.
    ///
    /// Falls back to parallel individual requests if the batch result can't be split
    /// reliably, or if the combined text is too long.
    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        // Single text — no batching needed
        if texts.count == 1 {
            let result = try await translate(texts[0], from: from, to: to)
            return [result]
        }

        // Combine texts separated by newline — Google preserves line breaks
        let combined = texts.joined(separator: "\n")

        // If combined text is too long for one request, use parallel
        if combined.count > 3500 {
            return try await translateParallel(texts, from: from, to: to)
        }

        do {
            let translated = try await translate(combined, from: from, to: to)
            if let parts = Self.splitBatch(translated, count: texts.count) {
                return parts
            }

            // Google merged or split lines — we can't tell which translation belongs
            // to which text, so translate each one on its own
            GameLog.log("Batch split mismatch (expected \(texts.count) lines), using parallel")
            return try await translateParallel(texts, from: from, to: to)
        } catch {
            // Batch failed — fall back to parallel
            return try await translateParallel(texts, from: from, to: to)
        }
    }

    /// Split a newline-joined batch reply back into one translation per text.
    /// Returns nil when the line count doesn't match: rejoining or padding lines
    /// would shift every later translation onto the wrong text.
    static func splitBatch(_ translated: String, count: Int) -> [String]? {
        let parts = translated.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == count ? parts : nil
    }

    /// Parallel translation: each text in its own concurrent request
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
