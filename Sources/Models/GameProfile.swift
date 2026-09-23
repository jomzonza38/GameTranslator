import Foundation

/// Per-game settings, keyed by the captured application's name
struct GameProfile: Codable, Equatable {
    /// Title used in LLM prompts (editable, defaults to the app name)
    var title: String
    /// Fixed translations for names and terms in this game
    var glossary: [GlossaryEntry] = []
}

/// A fixed source → Thai translation for a game-specific term
struct GlossaryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var source: String
    var target: String
}

extension GlossaryEntry {
    /// Both sides filled in
    var isUsable: Bool {
        !source.trimmingCharacters(in: .whitespaces).isEmpty &&
        !target.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether this entry's source term occurs in `text` (case-insensitive)
    func appears(in text: String) -> Bool {
        let term = source.trimmingCharacters(in: .whitespaces)
        return !term.isEmpty && text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Whether `text` is exactly this term (ignoring case and surrounding spaces/punctuation)
    func matchesExactly(_ text: String) -> Bool {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let a = text.trimmingCharacters(in: trim)
        let b = source.trimmingCharacters(in: trim)
        return !b.isEmpty && a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
