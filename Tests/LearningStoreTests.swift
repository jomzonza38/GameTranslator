import XCTest
@testable import GameTranslator

@MainActor
final class LearningStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        // A temp folder — never the owner's Application Support data
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LearningStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> LearningStore {
        LearningStore(directory: directory, saveDelay: 60)
    }

    // AC-1

    func testSameOriginalInOneGameIsStoredOnce() {
        let store = makeStore()
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "Graveyard Keeper", languageCode: "en")
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "Graveyard Keeper", languageCode: "en")
        let sentences = store.data(for: "Graveyard Keeper").sentences
        XCTAssertEqual(sentences.count, 1)
        XCTAssertEqual(sentences.first?.timesSeen, 2)
    }

    func testSameTextInTwoGamesIsTwoSentences() {
        let store = makeStore()
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "Game A", languageCode: "en")
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "Game B", languageCode: "en")
        XCTAssertEqual(store.data(for: "Game A").sentences.count, 1)
        XCTAssertEqual(store.data(for: "Game B").sentences.count, 1)
        XCTAssertEqual(store.games, ["Game A", "Game B"])
    }

    // AC-2

    func testEnglishWordsAreBaseFormsWithoutFunctionWords() {
        let words = WordExtractor.words(in: "The knights drew their swords.", languageCode: "en").map(\.text)
        XCTAssertTrue(words.contains("knight"), "\(words)")
        XCTAssertTrue(words.contains("draw") || words.contains("drew"), "\(words)")
        XCTAssertTrue(words.contains("sword"), "\(words)")
        XCTAssertFalse(words.contains("the"))
        XCTAssertFalse(words.contains("their"))
        XCTAssertFalse(words.contains { $0.contains(".") })
    }

    func testNumbersAndSingleLettersGiveNothing() {
        let store = makeStore()
        for text in ["15", "7/1", "x"] {
            XCTAssertTrue(WordExtractor.words(in: text, languageCode: "en").isEmpty, text)
            store.add(original: text, translation: text, game: "G", languageCode: "en")
        }
        XCTAssertTrue(store.data(for: "G").sentences.isEmpty)
        XCTAssertTrue(store.data(for: "G").words.isEmpty)
    }

    func testWordsCollectExamplesAndCounts() {
        let store = makeStore()
        let words = WordExtractor.words(in: "Sharpen the sword", languageCode: "en")
        store.addWords(words, from: "Sharpen the sword", game: "G")
        store.addWords(WordExtractor.words(in: "A rusty sword", languageCode: "en"), from: "A rusty sword", game: "G")
        let sword = store.data(for: "G").words.first { $0.word == "sword" }
        XCTAssertEqual(sword?.timesSeen, 2)
        XCTAssertEqual(sword?.examples, ["Sharpen the sword", "A rusty sword"])
    }

    func testJapaneseIsSplitIntoWords() {
        let words = WordExtractor.words(in: "剣を研ぐ", languageCode: "ja").map(\.text)
        XCTAssertFalse(words.isEmpty)
    }

    // AC-3

    func testSaveAndLoadKeepEverything() throws {
        let store = makeStore()
        store.add(original: "Open the gate", translation: "เปิดประตู", game: "G", languageCode: "en")
        store.addWords([.init(text: "gate", partOfSpeech: "Noun")], from: "Open the gate", game: "G")
        let sentenceID = try XCTUnwrap(store.data(for: "G").sentences.first?.id)
        let wordID = try XCTUnwrap(store.data(for: "G").words.first?.id)
        store.setKnown(sentence: sentenceID, in: "G", true)
        store.setKnown(word: wordID, in: "G", true)
        try store.saveNow()

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.file, store.file)
        XCTAssertEqual(reloaded.data(for: "G").sentences.first?.isKnown, true)
        XCTAssertEqual(reloaded.data(for: "G").words.first?.partOfSpeech, "Noun")
    }

    func testCorruptFileLoadsEmptyAndIsMovedAside() throws {
        let url = directory.appendingPathComponent("learning.json")
        try Data("{ not json".utf8).write(to: url)

        let store = makeStore()
        XCTAssertTrue(store.file.games.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "broken file moved away, not overwritten")
        let aside = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("learning.corrupt-") }
        XCTAssertEqual(aside.count, 1)
        let kept = try String(contentsOf: directory.appendingPathComponent(aside[0]), encoding: .utf8)
        XCTAssertEqual(kept, "{ not json")
    }

    func testMissingFileLoadsEmpty() {
        XCTAssertTrue(makeStore().file.games.isEmpty)
    }

    // AC-4

    func testSizeLimitDropsOldestUnmarkedFirstAndKeepsKnown() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        func sentence(_ text: String, seen: Int, age: Double, known: Bool = false) -> LearningSentence {
            LearningSentence(original: text, translation: text, firstSeen: base.addingTimeInterval(age),
                             lastSeen: base.addingTimeInterval(age), timesSeen: seen, isKnown: known)
        }
        func word(_ text: String, example: String, seen: Int, age: Double, known: Bool = false) -> LearningWord {
            LearningWord(word: text, partOfSpeech: nil, examples: [example], firstSeen: base.addingTimeInterval(age),
                         lastSeen: base.addingTimeInterval(age), timesSeen: seen, isKnown: known)
        }
        let data = GameLearningData(
            sentences: [
                sentence("old known", seen: 1, age: 0, known: true),
                sentence("old", seen: 1, age: 1),
                sentence("new", seen: 1, age: 10),
                sentence("often", seen: 9, age: 2),
            ],
            words: [
                word("kept", example: "old known", seen: 1, age: 0),   // word of a known sentence
                word("oldword", example: "old", seen: 1, age: 1),
                word("knownword", example: "x", seen: 1, age: 0, known: true),
                word("newword", example: "new", seen: 1, age: 10),
            ]
        )
        let trimmed = LearningStore.trimmed(data, maxSentences: 3, maxWords: 3)
        XCTAssertEqual(Set(trimmed.sentences.map(\.original)), ["old known", "new", "often"])
        XCTAssertEqual(Set(trimmed.words.map(\.word)), ["kept", "knownword", "newword"])
    }
}
