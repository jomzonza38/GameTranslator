import Foundation

/// In-memory log of translated lines for the history window
@MainActor
final class TranslationHistory: ObservableObject {
    static let shared = TranslationHistory()

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let game: String
        let original: String
        let translation: String
    }

    /// Oldest first
    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 1000
    /// Skip a line if it already appeared this many entries back (menus and HUD text repeat constantly)
    private let duplicateWindow = 50

    private init() {}

    func add(original: String, translation: String, game: String) {
        let recent = entries.suffix(duplicateWindow)
        guard !recent.contains(where: { $0.original == original && $0.game == game }) else { return }

        entries.append(Entry(date: Date(), game: game, original: original, translation: translation))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }

    /// Plain-text export, one block per line
    func exportText(_ items: [Entry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return items.map { entry in
            "[\(formatter.string(from: entry.date))] \(entry.game)\n\(entry.original)\n→ \(entry.translation)\n"
        }.joined(separator: "\n")
    }
}
