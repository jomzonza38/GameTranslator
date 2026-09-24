import SwiftUI

/// "📚 เรียนรู้คำศัพท์" — sentences and words collected from each game (T-0022)
struct LearningView: View {
    @ObservedObject private var store = LearningStore.shared
    @ObservedObject private var settings = AppSettings.shared

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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
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
                List(items) { sentence in
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
                List(items) { word in
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
                Text("ความหมาย: —")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
