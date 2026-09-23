import Foundation

/// Holds the pipeline state (text tracker, caches) for each capture region.
/// When no regions are defined, a single "global" state is used.
final class RegionPipelineState {
    let textTracker = TextTracker()
    /// Translations for texts currently on screen
    var cachedTranslations: [String: String] = [:]
    /// Translations of texts that just left the screen, kept for a grace period
    var staleTranslations: [String: (translation: String, expiry: CFAbsoluteTime)] = [:]
    /// Texts seen in the previous frame (used to wait until text stops changing)
    var previousFrameTexts: [String] = []
    /// When a translation request for a text last failed (for retry back-off)
    var failedAt: [String: CFAbsoluteTime] = [:]
    var lastLoggedTextCount = -1

    func reset() {
        textTracker.reset()
        cachedTranslations.removeAll()
        staleTranslations.removeAll()
        previousFrameTexts.removeAll()
        failedAt.removeAll()
        lastLoggedTextCount = -1
    }

    /// Current translation for `text`, including stale entries
    func translation(for text: String) -> String? {
        cachedTranslations[text] ?? staleTranslations[text]?.translation
    }

    /// Translation of an already-translated text that differs from `text` only by
    /// OCR noise (a misread letter or punctuation). Reusing it keeps the on-screen
    /// translation from changing — and costs no API call.
    func similarTranslation(for text: String) -> String? {
        let allowedEdits = max(1, text.count / 10)
        var best: (translation: String, distance: Int)?

        let candidates = cachedTranslations.map { ($0.key, $0.value) } +
            staleTranslations.map { ($0.key, $0.value.translation) }

        for (key, translation) in candidates {
            guard abs(key.count - text.count) <= allowedEdits else { continue }
            let distance = TextTracker.levenshteinDistance(key, text)
            guard distance <= allowedEdits else { continue }
            if best == nil || distance < best!.distance {
                best = (translation, distance)
            }
        }
        return best?.translation
    }

    /// Whether `text` looked the same in the previous frame. Text that is still being
    /// typed out (typewriter effect) or animating is not translated until it settles,
    /// which avoids translating half sentences and re-translating every frame.
    func isStable(_ text: String) -> Bool {
        Self.isStable(text, previousTexts: previousFrameTexts)
    }

    static func isStable(_ text: String, previousTexts: [String]) -> Bool {
        previousTexts.contains { previous in
            if previous == text { return true }
            // Growing text (typewriter): the new text extends the previous one
            if text.count > previous.count && text.hasPrefix(previous) { return false }
            // OCR jitter: same length ±1 and nearly identical
            return abs(previous.count - text.count) <= 1 &&
                TextTracker.similarity(previous, text) >= 0.85
        }
    }
}
