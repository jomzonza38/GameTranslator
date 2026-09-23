import Foundation

/// Orchestrates translation using the selected provider with caching
final class TranslationService: @unchecked Sendable {
    private var provider: TranslationProvider
    private let cache: TranslationCache
    private let settings: AppSettings

    /// Source language code
    let sourceLanguage = "en"
    /// Target language code
    let targetLanguage = "th"

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.cache = TranslationCache()
        self.provider = TranslationService.createProvider(for: settings.selectedProvider, settings: settings)
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

    /// Translate multiple texts, using cache where possible
    func translateBatch(_ texts: [String]) async throws -> [String: String] {
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

            let translations = try await provider.translateBatch(uncachedTexts, from: sourceLanguage, to: targetLanguage)

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
