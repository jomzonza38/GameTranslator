import XCTest
@testable import GameTranslator

/// Google stand-in that records the source language it was asked to translate from
private final class RecordingGoogle: TranslationProvider, @unchecked Sendable {
    let name = "Recording Google"
    let limitDescription = ""
    let requiresApiKey = false
    private let lock = NSLock()
    private var sources: [String] = []
    var fromLanguages: [String] { lock.withLock { sources } }

    func translate(_ text: String, from: String, to: String) async throws -> String { "ความหมาย" }

    func translateBatch(_ texts: [String], from: String, to: String) async throws -> [String] {
        lock.withLock { sources.append(from) }
        return texts.map { _ in "ความหมาย" }
    }
}

private final class PromptRecordingLLM: LLMChatProvider, @unchecked Sendable {
    let name = "Recording LLM"
    let limitDescription = ""
    let requiresApiKey = false
    private let lock = NSLock()
    private var systems: [String] = []
    var systemPrompts: [String] { lock.withLock { systems } }

    func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        lock.withLock { systems.append(system) }
        return "[1] noun | ดาบ"
    }
}

@MainActor
final class LearningDataCorrectnessTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LearningCorrectness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func waitUntilIdle(_ service: MeaningService) async {
        for _ in 0..<200 where service.isWorking {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // AC-1: language per game

    func testGameKeepsItsLanguageAcrossSaveAndLoad() throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "剣を研ぐ", translation: "ลับดาบ", game: "JP Game", languageCode: "ja")
        try store.saveNow()
        let reloaded = LearningStore(directory: directory, saveDelay: 60)
        XCTAssertEqual(reloaded.data(for: "JP Game").languageCode, "ja")
        XCTAssertEqual(reloaded.sourceLanguage(for: "JP Game", fallback: .english), .japanese)
    }

    func testGoogleLookupUsesTheGamesLanguageNotTheSetting() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "剣を研ぐ", translation: "ลับดาบ", game: "JP Game", languageCode: "ja")
        store.addWords([.init(text: "剣", partOfSpeech: "Noun")], from: "剣を研ぐ", game: "JP Game")
        let id = try XCTUnwrap(store.data(for: "JP Game").words.first?.id)

        let google = RecordingGoogle()
        let service = MeaningService(store: store, keyFor: { _ in "" }, google: google,
                                     chatProvider: { nil }, selectedProvider: { .googleFree },
                                     fallbackLanguage: { .english })
        service.lookUp(wordIDs: [id], game: "JP Game")
        await waitUntilIdle(service)
        XCTAssertEqual(google.fromLanguages, ["ja"])
    }

    func testLLMPromptNamesTheGamesLanguage() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "剣を研ぐ", translation: "ลับดาบ", game: "JP Game", languageCode: "ja")
        store.addWords([.init(text: "剣", partOfSpeech: "Noun")], from: "剣を研ぐ", game: "JP Game")
        let id = try XCTUnwrap(store.data(for: "JP Game").words.first?.id)

        let llm = PromptRecordingLLM()
        let service = MeaningService(store: store, keyFor: { _ in "sk" }, makeLLM: { _, _ in llm },
                                     chatProvider: { nil }, selectedProvider: { .claudeHaiku },
                                     fallbackLanguage: { .english })
        service.lookUp(wordIDs: [id], game: "JP Game")
        await waitUntilIdle(service)
        XCTAssertTrue(llm.systemPrompts.first?.contains("learn Japanese") == true, "\(llm.systemPrompts)")
    }

    func testDataWithoutALanguageFallsBackToTheSetting() throws {
        let json = #"{"version":1,"games":{"Old":{"sentences":[],"words":[]}}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("learning.json"))
        let store = LearningStore(directory: directory, saveDelay: 60)
        XCTAssertNil(store.data(for: "Old").languageCode)
        XCTAssertEqual(store.sourceLanguage(for: "Old", fallback: .korean), .korean)
    }

    // AC-2: saves in order

    func testASlowOlderWriteCannotOverwriteANewerOne() async throws {
        let lock = NSLock()
        var calls = 0
        let store = LearningStore(directory: directory, saveDelay: 0.01) { file, url in
            let call = lock.withLock { () -> Int in calls += 1; return calls }
            if call == 1 { Thread.sleep(forTimeInterval: 0.3) } // the first write is slow
            try LearningStore.write(file, to: url)
        }
        store.add(original: "First line", translation: "หนึ่ง", game: "G", languageCode: "en")
        try await Task.sleep(for: .milliseconds(80))   // first write is running
        store.add(original: "Second line", translation: "สอง", game: "G", languageCode: "en")
        try await Task.sleep(for: .milliseconds(700))  // both writes done

        let onDisk = LearningStore.load(from: directory.appendingPathComponent("learning.json"))
        XCTAssertEqual(Set(onDisk.games["G"]?.sentences.map(\.original) ?? []), ["First line", "Second line"])
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    func testQuitSaveDuringARunningWriteWritesTheNewestData() async throws {
        let store = LearningStore(directory: directory, saveDelay: 0.01) { file, url in
            if file.games["G"]?.sentences.count == 1 { Thread.sleep(forTimeInterval: 0.3) } // slow old write
            try LearningStore.write(file, to: url)
        }
        store.add(original: "First line", translation: "หนึ่ง", game: "G", languageCode: "en")
        try await Task.sleep(for: .milliseconds(80))   // slow write of the old data is running
        store.add(original: "Newest line", translation: "ใหม่", game: "G", languageCode: "en")
        XCTAssertTrue(store.hasUnsavedChanges)

        store.saveIfNeeded()                           // quit: waits, then writes the newest
        XCTAssertFalse(store.hasUnsavedChanges)
        let onDisk = LearningStore.load(from: directory.appendingPathComponent("learning.json"))
        XCTAssertTrue(onDisk.games["G"]?.sentences.contains { $0.original == "Newest line" } == true)
    }

    // AC-3: clear race

    func testClearedGameDoesNotComeBackWithWords() async throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "The knights drew their swords", translation: "อัศวินชักดาบ", game: "G", languageCode: "en")
        store.clear(game: "G")                          // before the background extraction ends
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(store.games.contains("G"))
    }

    func testWordsOfADeletedLineAreDropped() throws {
        let store = LearningStore(directory: directory, saveDelay: 60)
        store.add(original: "Keep this line", translation: "เก็บ", game: "G", languageCode: "en")
        store.add(original: "Delete this line", translation: "ลบ", game: "G", languageCode: "en")
        let deleted = try XCTUnwrap(store.data(for: "G").sentences.first { $0.original == "Delete this line" }?.id)
        store.delete(sentence: deleted, in: "G")
        store.applyExtractedWords([.init(text: "delete", partOfSpeech: "Verb")], from: "Delete this line", game: "G")
        XCTAssertFalse(store.data(for: "G").words.contains { $0.word == "delete" })

        store.applyExtractedWords([.init(text: "keep", partOfSpeech: "Verb")], from: "Keep this line", game: "G")
        XCTAssertTrue(store.data(for: "G").words.contains { $0.word == "keep" })
    }
}
