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
