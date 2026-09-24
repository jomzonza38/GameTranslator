import Foundation

/// DeepL Translation API provider
/// Supports both Free and Pro tiers
final class DeepLProvider: TranslationProvider {
    let name: String
    let limitDescription: String
    let requiresApiKey = true

    private let apiKey: String
    private let isPro: Bool
    private let baseURL: String
    /// One session for every instance: a provider is rebuilt whenever the API key or
    /// provider changes, and a session per instance was never released. Not
    /// invalidated either — a request still running on an old instance would crash
    /// on an invalidated session.
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let session = sharedSession

    /// Initialize DeepL provider
    /// - Parameters:
    ///   - apiKey: DeepL API key
    ///   - isPro: Whether this is a Pro account (affects API endpoint)
    init(apiKey: String, isPro: Bool = false) {
        self.apiKey = apiKey
        self.isPro = isPro
        self.name = isPro ? "DeepL Pro" : "DeepL Free"
        self.limitDescription = isPro
            ? "ไม่จำกัด (€5.49/เดือน + €25/ล้านตัวอักษร)"
            : "500,000 ตัวอักษร/เดือน"
        // Free API uses api-free.deepl.com, Pro uses api.deepl.com
        self.baseURL = isPro
            ? "https://api.deepl.com/v2/translate"
            : "https://api-free.deepl.com/v2/translate"
    }

    func warmUp() {
        guard let url = URL(string: baseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        session.dataTask(with: request).resume()
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
            URLQueryItem(name: "source_lang", value: mapLanguageCode(from, isSource: true)),
            URLQueryItem(name: "target_lang", value: mapLanguageCode(to, isSource: false))
        ]
        for text in texts {
            queryItems.append(URLQueryItem(name: "text", value: text))
        }
        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build form body manually since we have duplicate "text" keys.
        // .urlQueryAllowed leaves &, = and + unescaped, which would split the text.
        var formAllowed = CharacterSet.urlQueryAllowed
        formAllowed.remove(charactersIn: "&=+?/")
        let body = queryItems.map { item in
            let key = item.name.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: formAllowed) ?? ""
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

            // Only DeepL Free has a monthly limit the app enforces
            if !isPro {
                let totalChars = texts.reduce(0) { $0 + $1.count }
                await MainActor.run {
                    AppSettings.shared.addCharacterUsage(totalChars)
                }
            }

            return decoded.translations.map { $0.text }
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }

    /// Map standard language codes to DeepL-specific codes
    /// DeepL accepts only the base code ("ZH") for source languages,
    /// but needs the script variant ("ZH-HANS"/"ZH-HANT") for targets.
    private func mapLanguageCode(_ code: String, isSource: Bool) -> String {
        switch code.lowercased() {
        case "en": return isSource ? "EN" : "EN-US"
        case "th": return "TH"
        case "ja": return "JA"
        case "ko": return "KO"
        case "zh", "zh-cn", "zh-hans": return isSource ? "ZH" : "ZH-HANS"
        case "zh-tw", "zh-hant": return isSource ? "ZH" : "ZH-HANT"
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
