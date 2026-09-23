import Foundation

/// DeepL Translation API provider
/// Supports both Free and Pro tiers
final class DeepLProvider: TranslationProvider {
    let name: String
    let limitDescription: String
    let requiresApiKey = true

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession

    /// Initialize DeepL provider
    /// - Parameters:
    ///   - apiKey: DeepL API key
    ///   - isPro: Whether this is a Pro account (affects API endpoint)
    init(apiKey: String, isPro: Bool = false) {
        self.apiKey = apiKey
        self.name = isPro ? "DeepL Pro" : "DeepL Free"
        self.limitDescription = isPro
            ? "ไม่จำกัด (€5.49/เดือน + €25/ล้านตัวอักษร)"
            : "500,000 ตัวอักษร/เดือน"
        // Free API uses api-free.deepl.com, Pro uses api.deepl.com
        self.baseURL = isPro
            ? "https://api.deepl.com/v2/translate"
            : "https://api-free.deepl.com/v2/translate"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TranslationError.missingApiKey
        }

        let results = try await translateBatch([text], from: from, to: to)
        guard let first = results.first else {
            throw TranslationError.invalidResponse
        }
        return first
    }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        guard !apiKey.isEmpty else {
            throw TranslationError.missingApiKey
        }

        var urlComponents = URLComponents(string: baseURL)!
        var queryItems = [
            URLQueryItem(name: "source_lang", value: mapLanguageCode(from)),
            URLQueryItem(name: "target_lang", value: mapLanguageCode(to))
        ]
        for text in texts {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }
        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build form body manually since we have duplicate "text" keys
        let body = queryItems.map { item in
            let key = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(key)=\(value)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        request.url = URL(string: baseURL)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 403:
                throw TranslationError.missingApiKey
            case 429:
                throw TranslationError.rateLimitExceeded
            case 456:
                throw TranslationError.quotaExceeded(provider: name, limit: limitDescription)
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TranslationError.translationFailed(message: "HTTP \(httpResponse.statusCode): \(errorBody)")
            }

            let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)

            // Track usage
            let totalChars = texts.reduce(0) { $0 + $1.count }
            await MainActor.run {
                AppSettings.shared.addCharacterUsage(totalChars)
            }

            return decoded.translations.map { $0.text }
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }

    /// Map standard language codes to DeepL-specific codes
    private func mapLanguageCode(_ code: String) -> String {
        switch code.lowercased() {
        case "en": return "EN"
        case "th": return "TH"
        case "ja": return "JA"
        case "zh": return "ZH-HANS"
        case "ko": return "KO"
        default: return code.uppercased()
        }
    }
}

// MARK: - Response Models

private struct DeepLResponse: Decodable {
    let translations: [DeepLTranslation]
}

private struct DeepLTranslation: Decodable {
    let detectedSourceLanguage: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case detectedSourceLanguage = "detected_source_language"
        case text
    }
}
