import Foundation

/// LRU cache for translated texts to avoid redundant API calls
actor TranslationCache {
    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxEntries: Int

    struct CacheEntry {
        let originalText: String
        let translatedText: String
        let provider: String
        let timestamp: Date
    }

    init(maxEntries: Int = 10_000) {
        self.maxEntries = maxEntries
    }

    /// Look up a translation in cache
    func get(_ text: String) -> String? {
        guard let entry = cache[text] else { return nil }

        // Move to end of access order (most recently used)
        if let index = accessOrder.firstIndex(of: text) {
            accessOrder.remove(at: index)
            accessOrder.append(text)
        }

        return entry.translatedText
    }

    /// Store a translation in cache
    func set(_ text: String, translation: String, provider: String) {
        // Evict oldest if at capacity
        if cache.count >= maxEntries, let oldest = accessOrder.first {
            cache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }

        cache[text] = CacheEntry(
            originalText: text,
            translatedText: translation,
            provider: provider,
            timestamp: Date()
        )

        // Remove from current position if exists, add to end
        if let index = accessOrder.firstIndex(of: text) {
            accessOrder.remove(at: index)
        }
        accessOrder.append(text)
    }

    /// Check if a translation exists in cache
    func contains(_ text: String) -> Bool {
        cache[text] != nil
    }

    /// Clear all cached translations
    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    /// Number of cached entries
    var count: Int {
        cache.count
    }

    /// Get cache hit statistics
    var stats: (entries: Int, oldestAge: TimeInterval?) {
        let oldest = accessOrder.first.flatMap { cache[$0]?.timestamp }
        return (cache.count, oldest.map { Date().timeIntervalSince($0) })
    }
}
