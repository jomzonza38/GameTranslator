import Foundation

/// Google Cloud Translation API v2 provider
final class GoogleCloudProvider: TranslationProvider {
    let name = "Google Cloud Translation"
    let limitDescription = "$20/ล้านตัวอักษร (ต้องมี GCP project + API Key)"
    let requiresApiKey = true

    private let apiKey: String
    private let baseURL = "https://translation.googleapis.com/language/translate/v2"
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

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func warmUp() {
        var request = URLRequest(url: URL(string: "https://translation.googleapis.com/")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        session.dataTask(with: request).resume()
    }

    func translate(_ text: String, from: String, to: String) async throws -> String {
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

        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "q": texts,
            "source": from,
            "target": to,
            "format": "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranslationError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 400:
                throw TranslationError.translationFailed(message: "Bad request")
            case 401, 403:
                throw TranslationError.missingApiKey
            case 429:
                throw TranslationError.rateLimitExceeded
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw TranslationError.translationFailed(message: "HTTP \(httpResponse.statusCode): \(errorBody)")
            }

            let decoded = try JSONDecoder().decode(GoogleTranslateResponse.self, from: data)

            return decoded.data.translations.map { translation in
                // Google returns HTML-encoded entities, decode them
                translation.translatedText
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
            }
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(underlying: error)
        }
    }
}

// MARK: - Response Models

private struct GoogleTranslateResponse: Decodable {
    let data: GoogleTranslateData
}

private struct GoogleTranslateData: Decodable {
    let translations: [GoogleTranslation]
}

private struct GoogleTranslation: Decodable {
    let translatedText: String
}
