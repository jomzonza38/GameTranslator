import SwiftUI

/// "📚 เรียนรู้คำศัพท์" — sentences and words collected from each game (T-0022)
struct LearningView: View {
    @ObservedObject private var store = LearningStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var meanings = MeaningService.shared

    enum Tab: String, CaseIterable, Identifiable {
        case sentences = "ประโยค"
        case words = "คำศัพท์"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case newest = "ล่าสุด"
        case mostSeen = "เห็นบ่อย"
        case alphabetical = "A–Z"
        var id: String { rawValue }
    }

    @State private var game = ""
    @State private var tab: Tab = .sentences
    @State private var searchText = ""
    @State private var sort: Sort = .newest
    @AppStorage("learningHideKnown") private var hideKnown = true
    @State private var confirmClear = false
    /// Item shown in the detail pane (T-0023)
    @State private var selectedSentence: UUID?
    @State private var selectedWord: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                content
                detail
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 440)
        .onAppear(perform: chooseDefaultGame)
        .onChange(of: store.games) { _, _ in
            if !store.games.contains(game) { chooseDefaultGame() }
        }
        .confirmationDialog("ล้างรายการทั้งหมดของ \(game)?", isPresented: $confirmClear) {
            Button("ล้างทั้งหมด", role: .destructive) { store.clear(game: game) }
        } message: {
            Text("ประโยคและคำศัพท์ของเกมนี้จะถูกลบ (รวมที่จำได้แล้ว)")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("เกม:", selection: $game) {
                    if store.games.isEmpty { Text("—").tag("") }
                    ForEach(store.games, id: \.self) { Text($0).tag($0) }
                }
                .frame(maxWidth: 260)

                Spacer()

                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ค้นหา", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("เรียง:", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 150)

                Toggle("ซ่อนที่จำได้แล้ว", isOn: $hideKnown)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(10)
    }

    // MARK: Lists

    @ViewBuilder
    private var content: some View {
        let data = store.data(for: game)
        switch tab {
        case .sentences:
            let items = filteredSentences(data.sentences)
            if items.isEmpty {
                emptyState(total: data.sentences.count)
            } else {
                List(items, selection: $selectedSentence) { sentence in
                    SentenceRow(sentence: sentence) {
                        store.setKnown(sentence: sentence.id, in: game, !sentence.isKnown)
                    }
                    .contextMenu {
                        Button("ลบ", role: .destructive) { store.delete(sentence: sentence.id, in: game) }
                    }
                }
                .listStyle(.inset)
            }
        case .words:
            let items = filteredWords(data.words)
            if items.isEmpty {
                emptyState(total: data.words.count)
            } else {
                List(items, selection: $selectedWord) { word in
                    WordRow(word: word) {
                        store.setKnown(word: word.id, in: game, !word.isKnown)
                    }
                    .contextMenu {
                        Button("ลบ", role: .destructive) { store.delete(word: word.id, in: game) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func emptyState(total: Int) -> some View {
        VStack {
            Spacer()
            Text(total == 0
                 ? "ยังไม่มีรายการ — ประโยคและคำศัพท์จะถูกเก็บไว้ที่นี่ระหว่างแปลเกม"
                 : "ไม่พบรายการ (ลองล้างคำค้นหา หรือปิด \"ซ่อนที่จำได้แล้ว\")")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        let data = store.data(for: game)
        let shown = tab == .sentences ? filteredSentences(data.sentences).count : filteredWords(data.words).count
        let total = tab == .sentences ? data.sentences.count : data.words.count
        return HStack {
            Text("แสดง \(shown) จาก \(total) \(tab == .sentences ? "ประโยค" : "คำ")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if tab == .words {
                lookupControls(words: filteredWords(data.words))
            }
            Spacer()
            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label("ล้างรายการของเกมนี้", systemImage: "trash")
            }
            .disabled(game.isEmpty || (data.sentences.isEmpty && data.words.isEmpty))
        }
        .padding(8)
    }

    // MARK: Meanings (T-0023)

    @ViewBuilder
    private func lookupControls(words: [LearningWord]) -> some View {
        let missing = words.filter { $0.meaning == nil }
        if meanings.isWorking {
            ProgressView().controlSize(.small)
            Button("หยุด") { meanings.cancel() }
        } else {
            Button {
                meanings.lookUp(
                    wordIDs: missing.map(\.id), game: game,
                    sourceLanguage: settings.sourceLanguage.englishName,
                    sourceCode: settings.sourceLanguage.translationCode
                )
            } label: {
                Label("หาความหมาย\(missing.isEmpty ? "" : " (\(min(missing.count, MeaningService.batchSize)))")", systemImage: "text.book.closed")
            }
            .disabled(missing.isEmpty)
            .help("หาความหมายของคำที่แสดงอยู่และยังไม่มีความหมาย ครั้งละไม่เกิน \(MeaningService.batchSize) คำ")
        }
        if let error = meanings.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if meanings.lastUsedGoogle {
            Text("ความหมายจาก Google (ไม่มีบริบท) — ใส่ API key ของ Claude/OpenAI จะได้ความหมายตามเกม")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var detail: some View {
        let data = store.data(for: game)
        if tab == .words, let id = selectedWord, let word = data.words.first(where: { $0.id == id }) {
            Divider()
            WordDetail(word: word, game: game, meanings: meanings, settings: settings,
                       chatContext: chatContext(original: word.word, translation: word.meaning))
                .id(word.id)
                .frame(width: 300)
        } else if tab == .sentences, let id = selectedSentence, let sentence = data.sentences.first(where: { $0.id == id }) {
            Divider()
            SentenceDetail(sentence: sentence, game: game, meanings: meanings, settings: settings,
                           chatContext: chatContext(original: sentence.original, translation: sentence.translation))
                .id(sentence.id)
                .frame(width: 300)
        }
    }

    /// What "💬 ถาม AI" talks about (T-0025)
    private func chatContext(original: String, translation: String?) -> ChatItemContext {
        ChatItemContext(
            original: original,
            translation: translation,
            gameTitle: game,
            sourceLanguage: settings.sourceLanguage.englishName,
            glossary: settings.gameProfiles.values.first { $0.title == game }?.glossary ?? []
        )
    }

    // MARK: Filtering

    private func filteredSentences(_ sentences: [LearningSentence]) -> [LearningSentence] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let items = sentences.filter { sentence in
            (!hideKnown || !sentence.isKnown) &&
            (query.isEmpty || sentence.original.localizedCaseInsensitiveContains(query)
                || sentence.translation.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .newest: return items.sorted { $0.lastSeen > $1.lastSeen }
        case .mostSeen: return items.sorted { ($0.timesSeen, $0.lastSeen) > ($1.timesSeen, $1.lastSeen) }
        case .alphabetical: return items.sorted { $0.original.localizedCaseInsensitiveCompare($1.original) == .orderedAscending }
        }
    }

    private func filteredWords(_ words: [LearningWord]) -> [LearningWord] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let items = words.filter { word in
            (!hideKnown || !word.isKnown) &&
            (query.isEmpty || word.word.localizedCaseInsensitiveContains(query)
                || word.examples.contains { $0.localizedCaseInsensitiveContains(query) })
        }
        switch sort {
        case .newest: return items.sorted { $0.lastSeen > $1.lastSeen }
        case .mostSeen: return items.sorted { ($0.timesSeen, $0.lastSeen) > ($1.timesSeen, $1.lastSeen) }
        case .alphabetical: return items.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        }
    }

    /// The game being translated, else the last one with data, else the first
    private func chooseDefaultGame() {
        let games = store.games
        let current = settings.currentProfile.title
        if games.contains(current) {
            game = current
        } else if let last = store.file.lastGame, games.contains(last) {
            game = last
        } else {
            game = games.first ?? ""
        }
    }
}

// MARK: - Rows

private struct KnownButton: View {
    let isKnown: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isKnown ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isKnown ? Color.green : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(isKnown ? "จำได้แล้ว (กดเพื่อยกเลิก)" : "จำได้แล้ว")
    }
}

private struct SentenceRow: View {
    let sentence: LearningSentence
    let toggleKnown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KnownButton(isKnown: sentence.isKnown, toggle: toggleKnown)
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence.original)
                    .font(.body)
                    .textSelection(.enabled)
                Text(sentence.translation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("เห็น \(sentence.timesSeen) ครั้ง · ล่าสุด \(sentence.lastSeen.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct WordRow: View {
    let word: LearningWord
    let toggleKnown: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            KnownButton(isKnown: word.isKnown, toggle: toggleKnown)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(word.word)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                    if let pos = PartOfSpeech.thaiName(word.partOfSpeech) {
                        Text(pos)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("เห็น \(word.timesSeen) ครั้ง")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    Text("ความหมาย: \(word.meaning ?? "—")")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if word.meaningSource == "google" {
                        Text("Google")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if word.meaningSource == "ai" {
                        Text("AI")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                if let example = word.examples.last {
                    Text(example)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// Thai names for NaturalLanguage lexical classes
enum PartOfSpeech {
    static func thaiName(_ tag: String?) -> String? {
        guard let tag else { return nil }
        switch tag {
        case "Noun": return "คำนาม"
        case "Verb": return "คำกริยา"
        case "Adjective": return "คำคุณศัพท์"
        case "Adverb": return "คำกริยาวิเศษณ์"
        case "Pronoun": return "คำสรรพนาม"
        case "Interjection": return "คำอุทาน"
        case "Preposition": return "คำบุพบท"
        case "Conjunction": return "คำสันธาน"
        case "Determiner": return "คำกำหนด"
        case "Particle": return "คำช่วย"
        case "Idiom": return "สำนวน"
        case "OtherWord": return nil
        default: return tag
        }
    }
}

// MARK: - Detail panes (T-0023)

private struct WordDetail: View {
    let word: LearningWord
    let game: String
    @ObservedObject var meanings: MeaningService
    @ObservedObject var settings: AppSettings
    let chatContext: ChatItemContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(word.word)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
                if let pos = PartOfSpeech.thaiName(word.partOfSpeech) {
                    Text(pos).foregroundStyle(.secondary)
                }

                Group {
                    if let meaning = word.meaning {
                        Text(meaning)
                            .font(.title3)
                            .textSelection(.enabled)
                        if let note = word.meaningNote {
                            Text(note).font(.callout).foregroundStyle(.secondary)
                        }
                        if word.meaningSource == "google" {
                            Text("จาก Google — แปลคำเดี่ยว ไม่มีบริบทของเกม")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else if meanings.isWorking {
                        ProgressView("กำลังหาความหมาย…").controlSize(.small)
                    } else {
                        Text("ยังไม่มีความหมาย").foregroundStyle(.secondary)
                    }
                }

                Button("หาความหมายใหม่") { lookUp(force: true) }
                    .disabled(meanings.isWorking)

                if let error = meanings.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                if !word.examples.isEmpty {
                    Divider()
                    Text("ตัวอย่างจากเกม").font(.caption).foregroundStyle(.secondary)
                    ForEach(word.examples.reversed(), id: \.self) { example in
                        Text(example).font(.callout).textSelection(.enabled)
                    }
                }

                Divider()
                ChatPane(itemID: word.id, context: chatContext)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Opening a word without a meaning looks it up
        .onAppear { if word.meaning == nil { lookUp(force: false) } }
        .onChange(of: word.id) { _, _ in if word.meaning == nil { lookUp(force: false) } }
    }

    private func lookUp(force: Bool) {
        meanings.lookUp(
            wordIDs: [word.id], game: game,
            sourceLanguage: settings.sourceLanguage.englishName,
            sourceCode: settings.sourceLanguage.translationCode,
            force: force
        )
    }
}

private struct SentenceDetail: View {
    let sentence: LearningSentence
    let game: String
    @ObservedObject var meanings: MeaningService
    @ObservedObject var settings: AppSettings
    let chatContext: ChatItemContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(sentence.original)
                    .font(.title3)
                    .textSelection(.enabled)
                Text(sentence.translation)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                if let explanation = sentence.explanation {
                    Text(explanation)
                        .font(.callout)
                        .textSelection(.enabled)
                    Button("อธิบายใหม่") { explain(force: true) }
                        .disabled(meanings.isWorking)
                } else if meanings.isWorking {
                    ProgressView("กำลังอธิบาย…").controlSize(.small)
                } else {
                    // Pressing it without an AI key shows "ต้องมี API key…" (keys are only read on request)
                    Button("อธิบายประโยคนี้") { explain(force: false) }
                }

                if let error = meanings.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                Divider()
                ChatPane(itemID: sentence.id, context: chatContext)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func explain(force: Bool) {
        meanings.explain(sentenceID: sentence.id, game: game, sourceLanguage: settings.sourceLanguage.englishName, force: force)
    }
}

// MARK: - Chat (T-0025)

/// "💬 ถาม AI" about one sentence or word. Nothing is sent until the user presses send
/// or a quick question.
private struct ChatPane: View {
    let itemID: UUID
    let context: ChatItemContext
    @ObservedObject private var chat = LearningChatService.shared
    @State private var isOpen = false
    @State private var draft = ""

    private var turns: [ChatTurn] { chat.turns(for: itemID) }
    private var isWaitingHere: Bool { chat.sendingItem == itemID }

    var body: some View {
        if isOpen || !turns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("💬 ถาม AI").font(.headline)
                    Spacer()
                    Button("ล้างแชท") { chat.clear(item: itemID) }
                        .buttonStyle(.borderless)
                        .disabled(turns.isEmpty)
                }

                // Quick questions
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ChatPrompt.quickQuestions, id: \.self) { question in
                        Button(question) { chat.send(question, about: itemID, context: context) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(chat.isSending)
                    }
                }

                ForEach(turns) { turn in
                    bubble(turn)
                }

                if isWaitingHere {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("AI กำลังตอบ…").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("หยุด") { chat.stop() }
                            .controlSize(.small)
                    }
                }

                TextEditor(text: $draft)
                    .font(.callout)
                    .frame(height: 52)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    // Return sends; Shift-Return makes a new line
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        sendDraft()
                        return .handled
                    }

                HStack {
                    Text("Return ส่ง · Shift-Return ขึ้นบรรทัดใหม่")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("ส่ง") { sendDraft() }
                        .disabled(chat.isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        } else {
            Button("💬 ถาม AI") { isOpen = true }
        }
    }

    private func sendDraft() {
        guard !chat.isSending else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        chat.send(text, about: itemID, context: context)
    }

    @ViewBuilder
    private func bubble(_ turn: ChatTurn) -> some View {
        switch turn.role {
        case .user:
            Text(turn.text)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
                .textSelection(.enabled)
        case .assistant:
            Text(turn.text)
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12)))
                .textSelection(.enabled)
        case .notice:
            Text(turn.text)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

