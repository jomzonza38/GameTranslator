import Foundation

/// Protocol for translation service providers
protocol TranslationProvider {
    /// Display name of the provider
    var name: String { get }
    /// Description of usage limits
    var limitDescription: String { get }
    /// Whether this provider requires an API key
    var requiresApiKey: Bool { get }

    /// Translate text from source language to target language
    /// - Parameters:
    ///   - text: The text to translate
    ///   - from: Source language code (e.g., "en")
    ///   - to: Target language code (e.g., "th")
    /// - Returns: Translated text
    func translate(_ text: String, from: String, to: String) async throws -> String

    /// Translate multiple texts in a single batch request (if supported)
    /// Default implementation translates one by one
    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String]

    /// Batch translation with extra context (game title, previous lines, glossary).
    /// Providers that can't use context fall back to `translateBatch(_:from:to:)`.
    func translateBatch(_ texts: [String], from: String, to: String, context: TranslationContext) async throws -> [String]

    /// Open the HTTPS connection ahead of the first request (DNS + TLS take
    /// ~100-300 ms), so the first translation arrives sooner.
    func warmUp()
}

/// Extra information that helps context-aware (LLM) providers translate consistently
struct TranslationContext {
    /// Human-readable source language, e.g. "Japanese"
    var sourceLanguageName: String
    /// Game title for tone and terminology
    var gameTitle: String = ""
    /// Most recent translated lines, oldest first
    var recentLines: [(original: String, translation: String)] = []
    /// Fixed translations for game-specific terms
    var glossary: [GlossaryEntry] = []

    /// Context with only the source language, derived from a provider language code
    static func basic(from code: String) -> TranslationContext {
        let language = AppSettings.SourceLanguage.allCases.first {
            $0.translationCode == code || $0.rawValue == code
        }
        return TranslationContext(sourceLanguageName: language?.englishName ?? code)
    }
}

// Default batch implementation
extension TranslationProvider {
    func warmUp() {}

    func translateBatch(_ texts: [String], from: String, to: String, context: TranslationContext) async throws -> [String] {
        try await translateBatch(texts, from: from, to: to)
    }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
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

/// Errors that can occur during translation
enum TranslationError: LocalizedError {
    case missingApiKey
    case rateLimitExceeded
    case quotaExceeded(provider: String, limit: String)
    case networkError(underlying: Error)
    case invalidResponse
    case translationFailed(message: String)
    case unsupportedLanguage(language: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "API Key ไม่ได้ตั้งค่า กรุณาใส่ API Key ในหน้า Settings"
        case .rateLimitExceeded:
            return "ส่งคำขอเร็วเกินไป กรุณารอสักครู่"
        case .quotaExceeded(let provider, let limit):
            return "\(provider) ถึงขีดจำกัดแล้ว (\(limit)) กรุณาเปลี่ยน provider"
        case .networkError(let underlying):
            return "เชื่อมต่อไม่ได้: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "ได้รับข้อมูลที่ไม่ถูกต้องจาก API"
        case .translationFailed(let message):
            return "แปลไม่สำเร็จ: \(message)"
        case .unsupportedLanguage(let language):
            return "ไม่รองรับภาษา: \(language)"
        }
    }
}
