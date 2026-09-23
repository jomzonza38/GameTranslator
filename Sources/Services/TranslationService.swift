import Foundation

/// Orchestrates translation using the selected provider with caching
final class TranslationService: @unchecked Sendable {
    private var provider: TranslationProvider
    private let cache: TranslationCache
    private let settings: AppSettings

    /// Source language code (from Settings)
    var sourceLanguage: String { settings.sourceLanguage.translationCode }
    /// Target language code
    let targetLanguage = "th"

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.cache = TranslationCache()
        self.provider = TranslationService.createProvider(for: settings.selectedProvider, settings: settings)
    }

    /// Replace glossary terms in `text` with their Thai translation before sending it
    /// to a machine-translation provider (Google, DeepL), which can't take a glossary.
    /// Those services leave Thai words untouched, so the fixed term survives.
    static func applyGlossary(_ glossary: [GlossaryEntry], to text: String) -> String {
        var result = text
        // Longest terms first so "Dark Knight" wins over "Knight"
        for entry in glossary.sorted(by: { $0.source.count > $1.source.count }) {
            let term = entry.source.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { continue }
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.target)
            )
        }
        return result
    }

    /// Create provider instance based on type
    static func createProvider(for type: AppSettings.TranslationProviderType, settings: AppSettings) -> TranslationProvider {
        switch type {
        case .deeplFree:
            return DeepLProvider(apiKey: settings.deeplApiKey, isPro: false)
        case .deeplPro:
            return DeepLProvider(apiKey: settings.deeplApiKey, isPro: true)
        case .googleCloud:
            return GoogleCloudProvider(apiKey: settings.googleCloudApiKey)
        case .googleFree:
            return GoogleFreeProvider()
        case .openAI:
            return OpenAIProvider(apiKey: settings.openAIApiKey)
        case .claudeHaiku:
            return ClaudeProvider(apiKey: settings.claudeApiKey)
        }
    }

    /// Switch to a different translation provider
    func switchProvider(to type: AppSettings.TranslationProviderType) {
        provider = TranslationService.createProvider(for: type, settings: settings)
        provider.warmUp()
    }

    /// Translate a single text with caching
    func translate(_ text: String) async throws -> String {
        // Check cache first
        if let cached = await cache.get(text) {
            return cached
        }

        // Check usage limits before translating
        if settings.selectedProvider == .deeplFree && settings.isAtLimit() {
            throw TranslationError.quotaExceeded(
                provider: provider.name,
                limit: provider.limitDescription
            )
        }

        let translation = try await provider.translate(text, from: sourceLanguage, to: targetLanguage)

        // Cache the result
        await cache.set(text, translation: translation, provider: provider.name)

        return translation
    }

    /// Translate multiple texts, using cache where possible.
    /// `context` is used by LLM providers (game title, previous lines, glossary).
    func translateBatch(_ texts: [String], context: TranslationContext? = nil) async throws -> [String: String] {
        var results: [String: String] = [:]
        var uncachedTexts: [String] = []

        // Check cache for each text
        for text in texts {
            if let cached = await cache.get(text) {
                results[text] = cached
            } else {
                uncachedTexts.append(text)
            }
        }

        // Translate uncached texts
        if !uncachedTexts.isEmpty {
            // Check usage limits
            if settings.selectedProvider == .deeplFree && settings.isAtLimit() {
                throw TranslationError.quotaExceeded(
                    provider: provider.name,
                    limit: provider.limitDescription
                )
            }

            let requestContext = context ?? .basic(from: sourceLanguage)

            // LLM providers get the glossary in the prompt; others get terms pre-replaced
            var textsToSend = uncachedTexts
            if !(provider is LLMChatProvider) && !requestContext.glossary.isEmpty {
                textsToSend = uncachedTexts.map { Self.applyGlossary(requestContext.glossary, to: $0) }
            }

            let translations = try await provider.translateBatch(
                textsToSend,
                from: sourceLanguage,
                to: targetLanguage,
                context: requestContext
            )

            for (text, translation) in zip(uncachedTexts, translations) {
                results[text] = translation
                await cache.set(text, translation: translation, provider: provider.name)
            }
        }

        return results
    }

    /// Clear translation cache
    func clearCache() async {
        await cache.clear()
    }

    /// Get cache statistics
    func cacheStats() async -> (entries: Int, oldestAge: TimeInterval?) {
        await cache.stats
    }

    /// Current provider name
    var currentProviderName: String {
        provider.name
    }
}
