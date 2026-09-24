import Foundation
import NaturalLanguage

// MARK: - Model

/// A translated line kept for learning (T-0022)
struct LearningSentence: Codable, Identifiable, Equatable {
    var id = UUID()
    var original: String
    var translation: String
    var firstSeen: Date
    var lastSeen: Date
    var timesSeen: Int
    var isKnown = false
    /// Short Thai explanation from the AI (T-0023); nil until asked
    var explanation: String?
    /// Quiz answers (T-0024); nil until asked
    var quiz: QuizStats?
}

/// How an item has done in the quiz (T-0024)
struct QuizStats: Codable, Equatable {
    var correct = 0
    var wrong = 0
    /// Right answers in a row (reset by a wrong one)
    var streak = 0
    var lastAsked: Date?

    /// Answered right this many times in a row → suggest "จำได้แล้ว"
    static let knownStreak = 3
    var suggestsKnown: Bool { streak >= Self.knownStreak }

    mutating func record(correct isCorrect: Bool, at date: Date) {
        if isCorrect {
            correct += 1
            streak += 1
        } else {
            wrong += 1
            streak = 0
        }
        lastAsked = date
    }
}

/// A word found in translated lines — its base form (T-0022)
struct LearningWord: Codable, Identifiable, Equatable {
    var id = UUID()
    /// Lower-cased base form, e.g. "sword" for "Swords"
    var word: String
    /// NaturalLanguage lexical class ("Noun", "Verb", …) when known
    var partOfSpeech: String?
    /// A few lines the word appeared in (originals), newest last
    var examples: [String]
    var firstSeen: Date
    var lastSeen: Date
    var timesSeen: Int
    var isKnown = false
    /// Thai meaning (T-0023); nil until looked up
    var meaning: String?
    /// Where the meaning came from: "ai" (in context) or "google" (no context)
    var meaningSource: String?
    /// Short Thai note from the AI about the word in this game
    var meaningNote: String?
    /// Quiz answers (T-0024); nil until asked
    var quiz: QuizStats?

    static let maxExamples = 3
}

/// Everything learned from one game
struct GameLearningData: Codable, Equatable {
    var sentences: [LearningSentence] = []
    var words: [LearningWord] = []
    /// Source language the lines were collected in (`SourceLanguage.rawValue`; the latest
    /// if it changed). Nil for data saved before T-0026.
    var languageCode: String?
}

/// The file on disk
struct LearningFile: Codable, Equatable {
    var version = 1
    /// By game title (`GameProfile.title`)
    var games: [String: GameLearningData] = [:]
    /// The game something was last added for
    var lastGame: String?
}

// MARK: - Word extraction

/// Splits a translated line into learnable words, on-device (NaturalLanguage; no network,
/// no permission). English words get their base form ("swords" → "sword", "drew" →
/// "draw"); function words, numbers and single letters are skipped.
enum WordExtractor {
    struct Word: Equatable {
        let text: String
        let partOfSpeech: String?
    }

    /// Whether a line is worth keeping at all: it has at least two letters
    /// ("15", "7/1", "x" are not)
    static func isLearnable(_ text: String) -> Bool {
        text.filter(\.isLetter).count >= 2
    }

    static func words(in text: String, languageCode: String) -> [Word] {
        guard isLearnable(text) else { return [] }
        let language = NLLanguage(rawValue: languageCode)
        let isEnglish = languageCode.hasPrefix("en")

        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        var result: [Word] = []
        var seen = Set<String>()
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .omitOther]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            let token = String(text[range])
            guard token.contains(where: \.isLetter) else { return true }
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            let base = (lemma.flatMap { $0.isEmpty ? nil : $0 } ?? token).lowercased()

            // Latin script: single letters aren't words worth learning ("x", "a")
            let isLatin = base.unicodeScalars.allSatisfy { $0.isASCII }
            guard !(isLatin && base.count < 2) else { return true }
            guard !base.allSatisfy(\.isNumber) else { return true }
            if isEnglish, englishStopwords.contains(base) || englishStopwords.contains(token.lowercased()) { return true }
            if let tag, skippedClasses.contains(tag) { return true }
            guard seen.insert(base).inserted else { return true }
            result.append(Word(text: base, partOfSpeech: tag?.rawValue))
            return true
        }
        return result
    }

    /// Classes that are grammar, not vocabulary
    private static let skippedClasses: Set<NLTag> = [.number, .punctuation, .whitespace, .otherPunctuation, .sentenceTerminator]

    /// Very common English function words — not worth a vocabulary entry
    static let englishStopwords: Set<String> = [
        "the", "a", "an", "is", "am", "are", "was", "were", "be", "been", "being",
        "of", "to", "in", "on", "at", "by", "for", "with", "from", "as", "into", "about",
        "and", "or", "but", "if", "so", "than", "then", "that", "this", "these", "those",
        "it", "its", "he", "him", "his", "she", "her", "hers", "they", "them", "their", "theirs",
        "we", "us", "our", "ours", "you", "your", "yours", "i", "me", "my", "mine",
        "do", "does", "did", "have", "has", "had", "will", "would", "can", "could",
        "shall", "should", "may", "might", "must", "not", "no", "yes",
        "there", "here", "what", "which", "who", "whom", "whose", "when", "where", "why", "how",
        "all", "any", "some", "each", "every", "own", "just", "too", "very",
        "up", "down", "out", "off", "over", "again", "also", "only", "'s", "n't", "'re", "'ll", "'ve", "'m", "'d"
    ]
}

// MARK: - Store

/// Sentences and words from every real translation, per game, kept across launches in
/// `~/Library/Application Support/com.worawalan.GameTranslator/learning.json` (T-0022).
/// Adding costs the pipeline one in-memory update; word extraction runs off the main
/// actor and saving is debounced and done in the background.
@MainActor
final class LearningStore: ObservableObject {
    static let shared = LearningStore(directory: LearningStore.defaultDirectory)

    /// Size limits per game (oldest, least-seen, unmarked items go first)
    static let maxSentencesPerGame = 5_000
    static let maxWordsPerGame = 10_000

    @Published private(set) var file = LearningFile()

    let fileURL: URL
    private let saveDelay: TimeInterval
    private var saveTask: Task<Void, Never>?

    // Saving (T-0026): writes go through one serial queue, so they happen one at a time and
    // in order — the file always ends up with the newest snapshot.
    private let writeQueue = DispatchQueue(label: "com.worawalan.GameTranslator.learning-save", qos: .utility)
    private let writer: (LearningFile, URL) throws -> Void
    /// Bumped by every change
    private var changeCount = 0
    /// The newest change count whose snapshot has been written
    private var savedCount = 0
    /// Changes not written yet (only false once a write has actually finished)
    var hasUnsavedChanges: Bool { savedCount < changeCount }

    nonisolated static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("com.worawalan.GameTranslator", isDirectory: true)
    }

    init(
        directory: URL,
        saveDelay: TimeInterval = 1.0,
        writer: @escaping (LearningFile, URL) throws -> Void = LearningStore.write
    ) {
        self.fileURL = directory.appendingPathComponent("learning.json")
        self.saveDelay = saveDelay
        self.writer = writer
        self.file = Self.load(from: fileURL)
    }

    // MARK: Reading

    /// Games with learning data, sorted by name
    var games: [String] { file.games.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    func data(for game: String) -> GameLearningData {
        file.games[game] ?? GameLearningData()
    }

    /// The language a game's lines were collected in; `fallback` (the current setting) only
    /// for data saved before languages were stored (T-0026)
    func sourceLanguage(for game: String, fallback: AppSettings.SourceLanguage) -> AppSettings.SourceLanguage {
        file.games[game]?.languageCode.flatMap(AppSettings.SourceLanguage.init(rawValue:)) ?? fallback
    }

    // MARK: Adding (from the pipeline)

    /// Record a real translation. Returns quickly: words are extracted in the background.
    func add(original: String, translation: String, game: String, languageCode: String, now: Date = Date()) {
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard WordExtractor.isLearnable(text), !game.isEmpty else { return }

        var data = file.games[game] ?? GameLearningData()
        data.languageCode = languageCode
        if let index = data.sentences.firstIndex(where: { $0.original == text }) {
            data.sentences[index].timesSeen += 1
            data.sentences[index].lastSeen = now
            data.sentences[index].translation = translation
            file.games[game] = data
            file.lastGame = game
            scheduleSave()
            return
        }
        data.sentences.append(LearningSentence(original: text, translation: translation, firstSeen: now, lastSeen: now, timesSeen: 1))
        file.games[game] = Self.trimmed(data)
        file.lastGame = game
        scheduleSave()

        // Word extraction (NaturalLanguage) off the main actor, applied back here
        Task.detached(priority: .utility) { [weak self] in
            let words = WordExtractor.words(in: text, languageCode: languageCode)
            guard !words.isEmpty else { return }
            await self?.applyExtractedWords(words, from: text, game: game, now: now)
        }
    }

    /// Apply words from a background extraction — only if their line is still there. A
    /// game cleared (or a line deleted) meanwhile must not come back with words (T-0026).
    func applyExtractedWords(_ words: [WordExtractor.Word], from sentence: String, game: String, now: Date = Date()) {
        guard file.games[game]?.sentences.contains(where: { $0.original == sentence }) == true else { return }
        addWords(words, from: sentence, game: game, now: now)
    }

    /// Add extracted words synchronously (also used by tests)
    func addWords(_ words: [WordExtractor.Word], from sentence: String, game: String, now: Date = Date()) {
        var data = file.games[game] ?? GameLearningData()
        for word in words {
            if let index = data.words.firstIndex(where: { $0.word == word.text }) {
                data.words[index].timesSeen += 1
                data.words[index].lastSeen = now
                if data.words[index].partOfSpeech == nil { data.words[index].partOfSpeech = word.partOfSpeech }
                if !data.words[index].examples.contains(sentence) {
                    data.words[index].examples.append(sentence)
                    if data.words[index].examples.count > LearningWord.maxExamples {
                        data.words[index].examples.removeFirst(data.words[index].examples.count - LearningWord.maxExamples)
                    }
                }
            } else {
                data.words.append(LearningWord(
                    word: word.text, partOfSpeech: word.partOfSpeech, examples: [sentence],
                    firstSeen: now, lastSeen: now, timesSeen: 1
                ))
            }
        }
        file.games[game] = Self.trimmed(data)
        scheduleSave()
    }

    // MARK: Editing (from the Learning window)

    func setKnown(sentence id: UUID, in game: String, _ known: Bool) {
        mutate(game) { data in
            if let index = data.sentences.firstIndex(where: { $0.id == id }) { data.sentences[index].isKnown = known }
        }
    }

    func setKnown(word id: UUID, in game: String, _ known: Bool) {
        mutate(game) { data in
            if let index = data.words.firstIndex(where: { $0.id == id }) { data.words[index].isKnown = known }
        }
    }

    func delete(sentence id: UUID, in game: String) {
        mutate(game) { $0.sentences.removeAll { $0.id == id } }
    }

    func delete(word id: UUID, in game: String) {
        mutate(game) { $0.words.removeAll { $0.id == id } }
    }

    func clear(game: String) {
        file.games.removeValue(forKey: game)
        if file.lastGame == game { file.lastGame = nil }
        scheduleSave()
    }

    /// Change one game's data (later tasks: meanings, quiz stats)
    func mutate(_ game: String, _ change: (inout GameLearningData) -> Void) {
        guard var data = file.games[game] else { return }
        change(&data)
        file.games[game] = data
        scheduleSave()
    }

    // MARK: Quiz (T-0024)

    /// Store one quiz answer for a sentence or word
    func recordQuizAnswer(itemID: UUID, isWord: Bool, correct: Bool, in game: String, now: Date = Date()) {
        mutate(game) { data in
            if isWord, let index = data.words.firstIndex(where: { $0.id == itemID }) {
                var stats = data.words[index].quiz ?? QuizStats()
                stats.record(correct: correct, at: now)
                data.words[index].quiz = stats
            } else if !isWord, let index = data.sentences.firstIndex(where: { $0.id == itemID }) {
                var stats = data.sentences[index].quiz ?? QuizStats()
                stats.record(correct: correct, at: now)
                data.sentences[index].quiz = stats
            }
        }
    }

    // MARK: Size limit

    /// Keep a game's lists within the limits: drop unmarked items that were seen least
    /// and longest ago. Known items — and the words of known sentences — are kept.
    nonisolated static func trimmed(
        _ data: GameLearningData,
        maxSentences: Int = maxSentencesPerGame,
        maxWords: Int = maxWordsPerGame
    ) -> GameLearningData {
        var data = data
        if data.sentences.count > maxSentences {
            let excess = data.sentences.count - maxSentences
            let drop = Set(
                data.sentences.filter { !$0.isKnown }
                    .sorted { ($0.timesSeen, $0.lastSeen) < ($1.timesSeen, $1.lastSeen) }
                    .prefix(excess).map(\.id)
            )
            data.sentences.removeAll { drop.contains($0.id) }
        }
        if data.words.count > maxWords {
            let knownSentences = Set(data.sentences.filter(\.isKnown).map(\.original))
            let excess = data.words.count - maxWords
            let drop = Set(
                data.words.filter { !$0.isKnown && $0.examples.allSatisfy { !knownSentences.contains($0) } }
                    .sorted { ($0.timesSeen, $0.lastSeen) < ($1.timesSeen, $1.lastSeen) }
                    .prefix(excess).map(\.id)
            )
            data.words.removeAll { drop.contains($0.id) }
        }
        return data
    }

    // MARK: Persistence

    /// Read the file. Missing → empty. Unreadable → empty, logged, and the broken file
    /// moved aside so it is never silently overwritten.
    nonisolated static func load(from url: URL) -> LearningFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return LearningFile() }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .deferredToDate
            return try decoder.decode(LearningFile.self, from: data)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent().appendingPathComponent("learning.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            GameLog.log("Learning data unreadable (\(error.localizedDescription)) — starting empty; old file kept as \(aside.lastPathComponent)")
            return LearningFile()
        }
    }

    nonisolated static func write(_ file: LearningFile, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    /// Save after `saveDelay` of quiet. Encoding and writing happen on the serial write
    /// queue, off the main actor.
    private func scheduleSave() {
        changeCount += 1
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.enqueueWrite()
        }
    }

    private func enqueueWrite() {
        let snapshot = file
        let version = changeCount
        let url = fileURL
        let writer = self.writer
        writeQueue.async { [weak self] in
            do {
                try writer(snapshot, url)
                Task { @MainActor in self?.didWrite(version) }
            } catch {
                GameLog.log("Learning data save failed: \(error.localizedDescription)")
            }
        }
    }

    private func didWrite(_ version: Int) {
        savedCount = max(savedCount, version)
    }

    /// Write the newest data now, after any write already running (tests; app quit)
    func saveNow() throws {
        saveTask?.cancel()
        let snapshot = file
        let version = changeCount
        let url = fileURL
        let writer = self.writer
        try writeQueue.sync { try writer(snapshot, url) }
        didWrite(version)
    }

    /// App quit: write pending changes synchronously (a debounced save would be lost). Waits
    /// for a background write that is still running, then writes the newest data.
    func saveIfNeeded() {
        guard hasUnsavedChanges else { return }
        do {
            try saveNow()
        } catch {
            GameLog.log("Learning data save at quit failed: \(error.localizedDescription)")
        }
    }
}
