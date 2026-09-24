import Foundation

/// Multiple-choice questions from one game's learning data (T-0024). Pure and offline.
enum QuizGenerator {
    enum Kind: Equatable {
        /// Word → its Thai meaning
        case wordToMeaning
        /// Original line → the game's Thai translation
        case sentenceToTranslation
        /// Thai meaning → the word
        case meaningToWord
    }

    enum Mode: String, CaseIterable, Identifiable {
        case words = "คำศัพท์"
        case sentences = "ประโยค"
        case mixed = "ผสม"
        var id: String { rawValue }
    }

    struct Question: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind
        let itemID: UUID
        let isWord: Bool
        let prompt: String
        let choices: [String]
        let correctIndex: Int
        /// An example line shown with the answer (words)
        let example: String?

        var correctAnswer: String { choices[correctIndex] }
    }

    struct Quiz: Equatable {
        var questions: [Question]
        /// Why a kind couldn't be used (Thai), if any
        var notes: [String]
    }

    static let choiceCount = 4

    /// Words with a meaning / sentences with a translation that can be asked
    static func usableWords(_ data: GameLearningData, includeKnown: Bool) -> [LearningWord] {
        data.words.filter { ($0.meaning?.isEmpty == false) && (includeKnown || !$0.isKnown) }
    }

    static func usableSentences(_ data: GameLearningData, includeKnown: Bool) -> [LearningSentence] {
        data.sentences.filter { !$0.translation.isEmpty && (includeKnown || !$0.isKnown) }
    }

    /// Why a kind can't be offered (nil = it can)
    static func unavailableReason(words: [LearningWord]) -> String? {
        Set(words.compactMap(\.meaning)).count >= choiceCount ? nil : "ต้องมีคำที่มีความหมายอย่างน้อย \(choiceCount) คำ (กด หาความหมาย ในแท็บคำศัพท์)"
    }

    static func unavailableReason(sentences: [LearningSentence]) -> String? {
        Set(sentences.map(\.translation)).count >= choiceCount ? nil : "ต้องมีประโยคอย่างน้อย \(choiceCount) ประโยค"
    }

    /// Build a quiz. `onlyItems` limits it to those items (ทบทวนข้อที่ผิด).
    static func makeQuiz<R: RandomNumberGenerator>(
        from data: GameLearningData,
        count: Int,
        mode: Mode,
        includeKnown: Bool,
        onlyItems: Set<UUID>? = nil,
        using random: inout R
    ) -> Quiz {
        // Choices come from the whole usable set; questions from `onlyItems` if given
        let allWords = usableWords(data, includeKnown: includeKnown || onlyItems != nil)
        let allSentences = usableSentences(data, includeKnown: includeKnown || onlyItems != nil)
        var notes: [String] = []

        let wordsReason = mode == .sentences ? nil : unavailableReason(words: allWords)
        let sentencesReason = mode == .words ? nil : unavailableReason(sentences: allSentences)
        if let wordsReason { notes.append(wordsReason) }
        if let sentencesReason { notes.append(sentencesReason) }

        let canWords = mode != .sentences && wordsReason == nil
        let canSentences = mode != .words && sentencesReason == nil

        // Candidates, weighted towards weak items
        var candidates: [(id: UUID, isWord: Bool, weight: Double)] = []
        if canWords {
            candidates += allWords.filter { onlyItems?.contains($0.id) ?? true }
                .map { ($0.id, true, weight($0.quiz)) }
        }
        if canSentences {
            candidates += allSentences.filter { onlyItems?.contains($0.id) ?? true }
                .map { ($0.id, false, weight($0.quiz)) }
        }
        let picked = weightedSample(candidates, count: count, using: &random)

        var questions: [Question] = []
        for candidate in picked {
            if candidate.isWord, let word = allWords.first(where: { $0.id == candidate.id }) {
                if let question = wordQuestion(word, pool: allWords, using: &random) { questions.append(question) }
            } else if let sentence = allSentences.first(where: { $0.id == candidate.id }) {
                if let question = sentenceQuestion(sentence, pool: allSentences, using: &random) { questions.append(question) }
            }
        }
        return Quiz(questions: questions, notes: notes)
    }

    /// Higher = asked sooner. Never asked and often wrong go first; a right streak pushes
    /// an item back.
    static func weight(_ stats: QuizStats?) -> Double {
        guard let stats else { return 4 }
        return max(0.2, 1 + 2 * Double(stats.wrong) - 1.5 * Double(stats.streak))
    }

    /// Weighted sampling without replacement
    static func weightedSample<R: RandomNumberGenerator>(
        _ items: [(id: UUID, isWord: Bool, weight: Double)], count: Int, using random: inout R
    ) -> [(id: UUID, isWord: Bool, weight: Double)] {
        var pool = items
        var result: [(id: UUID, isWord: Bool, weight: Double)] = []
        while result.count < count, !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.weight }
            var target = Double.random(in: 0..<max(total, .leastNonzeroMagnitude), using: &random)
            var index = pool.count - 1
            for (i, item) in pool.enumerated() {
                target -= item.weight
                if target < 0 { index = i; break }
            }
            result.append(pool.remove(at: index))
        }
        return result
    }

    private static func wordQuestion<R: RandomNumberGenerator>(
        _ word: LearningWord, pool: [LearningWord], using random: inout R
    ) -> Question? {
        guard let meaning = word.meaning else { return nil }
        let others = pool.filter { $0.id != word.id }
        // Same part of speech first, then any
        let samePOS = others.filter { $0.partOfSpeech != nil && $0.partOfSpeech == word.partOfSpeech }
        let ordered = samePOS.shuffled(using: &random) + others.filter { !samePOS.contains($0) }.shuffled(using: &random)

        if Bool.random(using: &random) {
            let distractors = distinct(ordered.compactMap(\.meaning), excluding: meaning, count: choiceCount - 1)
            guard distractors.count == choiceCount - 1 else { return nil }
            return build(.wordToMeaning, itemID: word.id, isWord: true, prompt: word.word,
                         correct: meaning, distractors: distractors, example: word.examples.last, using: &random)
        } else {
            let distractors = distinct(ordered.filter { $0.meaning != meaning }.map(\.word), excluding: word.word, count: choiceCount - 1)
            guard distractors.count == choiceCount - 1 else { return nil }
            return build(.meaningToWord, itemID: word.id, isWord: true, prompt: meaning,
                         correct: word.word, distractors: distractors, example: word.examples.last, using: &random)
        }
    }

    private static func sentenceQuestion<R: RandomNumberGenerator>(
        _ sentence: LearningSentence, pool: [LearningSentence], using random: inout R
    ) -> Question? {
        let others = pool.filter { $0.id != sentence.id }.shuffled(using: &random)
        let distractors = distinct(others.map(\.translation), excluding: sentence.translation, count: choiceCount - 1)
        guard distractors.count == choiceCount - 1 else { return nil }
        return build(.sentenceToTranslation, itemID: sentence.id, isWord: false, prompt: sentence.original,
                     correct: sentence.translation, distractors: distractors, example: nil, using: &random)
    }

    private static func distinct(_ values: [String], excluding correct: String, count: Int) -> [String] {
        var seen: Set<String> = [correct]
        var result: [String] = []
        for value in values where !value.isEmpty && seen.insert(value).inserted {
            result.append(value)
            if result.count == count { break }
        }
        return result
    }

    private static func build<R: RandomNumberGenerator>(
        _ kind: Kind, itemID: UUID, isWord: Bool, prompt: String, correct: String,
        distractors: [String], example: String?, using random: inout R
    ) -> Question {
        var choices = distractors
        let index = Int.random(in: 0...choices.count, using: &random)
        choices.insert(correct, at: index)
        return Question(kind: kind, itemID: itemID, isWord: isWord, prompt: prompt,
                        choices: choices, correctIndex: index, example: example)
    }
}

/// Deterministic random numbers for tests (SplitMix64)
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
