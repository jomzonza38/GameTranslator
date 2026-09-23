import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Window listing past translations with search, copy and export
struct HistoryView: View {
    @ObservedObject private var history = TranslationHistory.shared
    @State private var searchText = ""

    private var filtered: [TranslationHistory.Entry] {
        let newestFirst = history.entries.reversed()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(newestFirst) }
        return newestFirst.filter {
            $0.original.localizedCaseInsensitiveContains(query) ||
            $0.translation.localizedCaseInsensitiveContains(query) ||
            $0.game.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ค้นหา", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button {
                    exportToFile()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(filtered.isEmpty)

                Button(role: .destructive) {
                    history.clear()
                } label: {
                    Label("ล้าง", systemImage: "trash")
                }
                .disabled(history.entries.isEmpty)
            }
            .padding(10)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text(history.entries.isEmpty ? "ยังไม่มีประวัติ — คำแปลจะมาแสดงที่นี่ระหว่างแปลเกม" : "ไม่พบข้อความที่ค้นหา")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }

            Divider()

            Text("\(history.entries.count) รายการ (เก็บเฉพาะระหว่างที่เปิดแอป สูงสุด 1,000)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "GameTranslator-history.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Export oldest first so it reads like a script
        let text = history.exportText(Array(filtered.reversed()))
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            GameLog.log("History export failed: \(error.localizedDescription)")
        }
    }
}

private struct HistoryRow: View {
    let entry: TranslationHistory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.date, style: .time)
                Text(entry.game)
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("\(entry.original)\n\(entry.translation)", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("คัดลอก")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(entry.translation)
                .font(.body)
                .textSelection(.enabled)
            Text(entry.original)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
