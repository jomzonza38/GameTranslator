import XCTest
@testable import GameTranslator

final class QuizGeneratorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func word(_ text: String, meaning: String?, pos: String? = "Noun", quiz: QuizStats? = nil, known: Bool = false) -> LearningWord {
        LearningWord(word: text, partOfSpeech: pos, examples: ["\(text) example"], firstSeen: now, lastSeen: now,
                     timesSeen: 1, isKnown: known, meaning: meaning, quiz: quiz)
    }

    private func sentence(_ text: String, _ thai: String, quiz: QuizStats? = nil) -> LearningSentence {
        LearningSentence(original: text, translation: thai, firstSeen: now, lastSeen: now, timesSeen: 1, quiz: quiz)
    }

    /// Built once per test (a computed property would make new UUIDs on every access)
    private lazy var sampleData: GameLearningData = makeSampleData()

    private func makeSampleData() -> GameLearningData {
        GameLearningData(
            sentences: (1...6).map { sentence("Line \($0)", "ประโยค \($0)") },
            words: [
                word("sword", meaning: "ดาบ"), word("shield", meaning: "โล่"), word("bone", meaning: "กระดูก"),
                word("stone", meaning: "หิน"), word("run", meaning: "วิ่ง", pos: "Verb"), word("dig", meaning: "ขุด", pos: "Verb"),
            ]
        )
    }

    // AC-1

    func testQuestionsHaveFourDistinctChoicesAndOneRightAnswer() {
        var random = SeededRandom(seed: 42)
        let quiz = QuizGenerator.makeQuiz(from: sampleData, count: 12, mode: .mixed, includeKnown: false, using: &random)
        XCTAssertEqual(quiz.questions.count, 12)
        var positions = Set<Int>()
        for question in quiz.questions {
            XCTAssertEqual(question.choices.count, 4)
            XCTAssertEqual(Set(question.choices).count, 4, "no duplicate choices")
            positions.insert(question.correctIndex)

            switch question.kind {
            case .wordToMeaning:
                let right = sampleData.words.first { $0.id == question.itemID }?.meaning
                XCTAssertEqual(question.correctAnswer, right)
                XCTAssertEqual(question.choices.filter { $0 == right }.count, 1)
                XCTAssertTrue(question.choices.allSatisfy { choice in sampleData.words.contains { $0.meaning == choice } }, "same game, same kind")
            case .meaningToWord:
                let right = sampleData.words.first { $0.id == question.itemID }?.word
                XCTAssertEqual(question.correctAnswer, right)
                XCTAssertTrue(question.choices.allSatisfy { choice in sampleData.words.contains { $0.word == choice } })
            case .sentenceToTranslation:
                let right = sampleData.sentences.first { $0.id == question.itemID }?.translation
                XCTAssertEqual(question.correctAnswer, right)
                XCTAssertTrue(question.choices.allSatisfy { choice in sampleData.sentences.contains { $0.translation == choice } })
            }
        }
        XCTAssertGreaterThan(positions.count, 1, "right answer position varies")
    }

    // AC-2

    func testTooFewItemsGiveNoQuestionAndAReason() {
        let data = GameLearningData(
            sentences: [sentence("A", "ก"), sentence("B", "ข")],
            words: [word("sword", meaning: "ดาบ"), word("shield", meaning: "โล่"), word("bone", meaning: nil)]
        )
        var random = SeededRandom(seed: 1)
        let quiz = QuizGenerator.makeQuiz(from: data, count: 10, mode: .mixed, includeKnown: false, using: &random)
        XCTAssertTrue(quiz.questions.isEmpty)
        XCTAssertEqual(quiz.notes.count, 2)
        XCTAssertTrue(quiz.notes.contains { $0.contains("อย่างน้อย 4 คำ") })
    }

    func testNoItemsIsAnEmptyQuiz() {
        var random = SeededRandom(seed: 1)
        let quiz = QuizGenerator.makeQuiz(from: GameLearningData(), count: 10, mode: .words, includeKnown: false, using: &random)
        XCTAssertTrue(quiz.questions.isEmpty)
    }

    func testSentencesOnlyWhenWordsHaveNoMeanings() {
        var data = sampleData
        for index in data.words.indices { data.words[index].meaning = nil }
        var random = SeededRandom(seed: 3)
        let quiz = QuizGenerator.makeQuiz(from: data, count: 5, mode: .mixed, includeKnown: false, using: &random)
        XCTAssertEqual(quiz.questions.count, 5)
        XCTAssertTrue(quiz.questions.allSatisfy { $0.kind == .sentenceToTranslation })
    }

    // AC-3

    func testWeakItemsArePickedBeforeWellKnownOnes() {
        var strong = QuizStats(); strong.correct = 5; strong.streak = 5
        var weak = QuizStats(); weak.wrong = 3
        let words = (0..<5).map { word("strong\($0)", meaning: "เก่ง\($0)", quiz: strong) }
            + (0..<3).map { word("weak\($0)", meaning: "อ่อน\($0)", quiz: weak) }
            + (0..<2).map { word("new\($0)", meaning: "ใหม่\($0)") }
        let data = GameLearningData(words: words)
        var random = SeededRandom(seed: 7)
        let quiz = QuizGenerator.makeQuiz(from: data, count: 5, mode: .words, includeKnown: false, using: &random)
        let picked = quiz.questions.compactMap { question in data.words.first { $0.id == question.itemID }?.word }
        XCTAssertEqual(picked.count, 5)
        XCTAssertGreaterThanOrEqual(picked.filter { !$0.hasPrefix("strong") }.count, 4, "\(picked)")
        XCTAssertGreaterThan(QuizGenerator.weight(weak), QuizGenerator.weight(strong))
        XCTAssertGreaterThan(QuizGenerator.weight(nil), QuizGenerator.weight(strong))
    }

    func testReviewOnlyAsksTheMissedItems() {
        let data = sampleData
        let missed: Set<UUID> = [data.words[0].id, data.sentences[1].id]
        var random = SeededRandom(seed: 9)
        let quiz = QuizGenerator.makeQuiz(from: data, count: 2, mode: .mixed, includeKnown: false, onlyItems: missed, using: &random)
        XCTAssertEqual(Set(quiz.questions.map(\.itemID)), missed)
    }
}

@MainActor
final class QuizStatsPersistenceTests: XCTestCase {
    // AC-4

    func testAnswerStatsAndKnownSuggestionSurviveSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuizStats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LearningStore(directory: directory, saveDelay: 60)
        store.addWords([.init(text: "sword", partOfSpeech: "Noun")], from: "Sharpen the sword", game: "G")
        let id = try XCTUnwrap(store.data(for: "G").words.first?.id)
        store.recordQuizAnswer(itemID: id, isWord: true, correct: false, in: "G")
        for _ in 0..<3 { store.recordQuizAnswer(itemID: id, isWord: true, correct: true, in: "G") }
        try store.saveNow()

        let stats = try XCTUnwrap(LearningStore(directory: directory, saveDelay: 60).data(for: "G").words.first?.quiz)
        XCTAssertEqual(stats.correct, 3)
        XCTAssertEqual(stats.wrong, 1)
        XCTAssertEqual(stats.streak, 3)
        XCTAssertNotNil(stats.lastAsked)
        XCTAssertTrue(stats.suggestsKnown)
    }

    func testOlderFilesWithoutNewFieldsStillLoad() throws {
        // A T-0022 file: no meaning / explanation / quiz fields
        let json = #"{"version":1,"games":{"G":{"sentences":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","original":"Open","translation":"เปิด","firstSeen":0,"lastSeen":0,"timesSeen":1,"isKnown":false}],"words":[]}}}"#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OldFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(json.utf8).write(to: directory.appendingPathComponent("learning.json"))
        let store = LearningStore(directory: directory, saveDelay: 60)
        XCTAssertEqual(store.data(for: "G").sentences.first?.original, "Open")
        XCTAssertNil(store.data(for: "G").sentences.first?.quiz)
    }
}
