import Foundation

/// Holds the pipeline state (text tracker, caches) for each capture region.
/// When no regions are defined, a single "global" state is used.
final class RegionPipelineState {
    let textTracker = TextTracker()
    /// Translations for texts currently on screen
    var cachedTranslations: [String: String] = [:]
    /// Translations of texts that just left the screen, kept for a grace period
    var staleTranslations: [String: (translation: String, expiry: CFAbsoluteTime)] = [:]
    var lastLoggedTextCount = -1

    func reset() {
        textTracker.reset()
        cachedTranslations.removeAll()
        staleTranslations.removeAll()
        lastLoggedTextCount = -1
    }

    /// Current translation for `text`, including stale entries
    func translation(for text: String) -> String? {
        cachedTranslations[text] ?? staleTranslations[text]?.translation
    }
}
