import Foundation

/// Tracks what LLM providers should know besides the text itself:
/// recently translated lines and the glossary currently in effect.
/// Holds no references to settings or UI, so it is easy to unit test.
final class TranslationContextBuilder {
    /// Lines sent with each request
    let contextLineCount: Int
    /// How long a glossary edit must stay unchanged before it is applied
    let settleDelay: CFAbsoluteTime

    /// Glossary entries currently used for translation
    private(set) var appliedGlossary: [GlossaryEntry] = []
    private var pendingGlossary: (entries: [GlossaryEntry], since: CFAbsoluteTime)?

    /// Recently translated lines, oldest first
    private(set) var recentLines: [(original: String, translation: String)] = []

    init(contextLineCount: Int = 6, settleDelay: CFAbsoluteTime = 1.5) {
        self.contextLineCount = contextLineCount
        self.settleDelay = settleDelay
    }

    /// Start fresh (new capture session) with the given glossary applied immediately
    func reset(glossary: [GlossaryEntry]) {
        appliedGlossary = glossary.filter(\.isUsable)
        pendingGlossary = nil
        recentLines.removeAll()
    }

    func clearRecentLines() {
        recentLines.removeAll()
    }

    func remember(original: String, translation: String) {
        if recentLines.last?.original == original { return }
        recentLines.append((original: original, translation: translation))
        let keep = contextLineCount * 2
        if recentLines.count > keep {
            recentLines.removeFirst(recentLines.count - keep)
        }
    }

    /// Fixed translation when `text` is exactly a glossary term
    func fixedTranslation(for text: String) -> String? {
        appliedGlossary.first(where: { $0.matchesExactly(text) })?.target
    }

    func context(
        for texts: [String],
        sourceLanguageName: String,
        gameTitle: String,
        includeRecentLines: Bool
    ) -> TranslationContext {
        // Only send glossary terms that occur in this batch to keep prompts short
        let relevantGlossary = appliedGlossary.filter { entry in
            texts.contains { entry.appears(in: $0) }
        }
        return TranslationContext(
            sourceLanguageName: sourceLanguageName,
            gameTitle: gameTitle,
            recentLines: includeRecentLines ? Array(recentLines.suffix(contextLineCount)) : [],
            glossary: relevantGlossary
        )
    }

    /// Feed the latest glossary from settings. An edit is applied only after it has
    /// stayed the same for `settleDelay` (so typing doesn't re-translate per keystroke).
    /// - Returns: true when a new glossary was just applied and cached translations
    ///   should be dropped.
    func updateGlossary(_ glossary: [GlossaryEntry], now: CFAbsoluteTime) -> Bool {
        let current = glossary.filter(\.isUsable)
        guard current != appliedGlossary else {
            pendingGlossary = nil
            return false
        }

        guard let pending = pendingGlossary, pending.entries == current else {
            pendingGlossary = (current, now)
            return false
        }
        guard now - pending.since >= settleDelay else { return false }

        appliedGlossary = current
        pendingGlossary = nil
        return true
    }
}
