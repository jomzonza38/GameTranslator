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

    /// Which provider and source language translations currently come from. Cached
    /// translations belong to one scope; the pipeline re-translates when it changes.
    var translationScope: String {
        Self.scope(provider: provider.name, sourceLanguage: sourceLanguage)
    }

    static func scope(provider: String, sourceLanguage: String) -> String {
        "\(provider)|\(sourceLanguage)"
    }

    /// Translate multiple texts, using cache where possible.
    /// `context` is used by LLM providers (game title, previous lines, glossary).
    /// Texts the provider gave no real translation for (LLM chatter) are left out of
    /// the result and not cached, so the caller retries them later.
    func translateBatch(_ texts: [String], context: TranslationContext? = nil) async throws -> [String: String] {
        try await Self.translateBatch(
            texts,
            with: provider,
            cache: cache,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            context: context ?? .basic(from: sourceLanguage),
            beforeRequest: { [settings, provider] in
                // DeepL Free: stop at the monthly limit (only when a request is needed)
                if settings.selectedProvider == .deeplFree && settings.isAtLimit() {
                    throw TranslationError.quotaExceeded(
                        provider: provider.name,
                        limit: provider.limitDescription
                    )
                }
            }
        )
    }

    /// The cache + provider logic of translateBatch, without AppSettings (testable
    /// with a fake provider). Cache entries are keyed by provider, source language
    /// and text, so another provider's or language's translation is never returned.
    static func translateBatch(
        _ texts: [String],
        with provider: TranslationProvider,
        cache: TranslationCache,
        sourceLanguage: String,
        targetLanguage: String,
        context: TranslationContext,
        beforeRequest: () throws -> Void = {}
    ) async throws -> [String: String] {
        let scope = scope(provider: provider.name, sourceLanguage: sourceLanguage)
        func cacheKey(_ text: String) -> String { "\(scope)\n\(text)" }

        var results: [String: String] = [:]
        var uncachedTexts: [String] = []
        for text in texts {
            if let cached = await cache.get(cacheKey(text)) {
                results[text] = cached
            } else {
                uncachedTexts.append(text)
            }
        }
        guard !uncachedTexts.isEmpty else { return results }

        try beforeRequest()

        // LLM providers get the glossary in the prompt; others get terms pre-replaced
        var textsToSend = uncachedTexts
        if !(provider is LLMChatProvider) && !context.glossary.isEmpty {
            textsToSend = uncachedTexts.map { applyGlossary(context.glossary, to: $0) }
        }

        let translations = try await provider.translateBatchMarkingFallbacks(
            textsToSend,
            from: sourceLanguage,
            to: targetLanguage,
            context: context
        )

        for (text, translation) in zip(uncachedTexts, translations) {
            // nil = the model answered with chatter: no translation, don't cache it
            guard let translation else { continue }
            results[text] = translation
            await cache.set(cacheKey(text), translation: translation, provider: provider.name)
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

    /// Whether the current provider needs an API key
    var currentProviderUsesApiKey: Bool {
        provider.requiresApiKey
    }
}
