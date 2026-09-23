import SwiftUI

/// Settings for the current game: prompt title and conversation context
struct GameSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("เกมปัจจุบัน") {
                if settings.gameProfiles.isEmpty {
                    Text("ยังไม่มีเกม — เริ่มแปลเกมสักครั้ง แล้วโปรไฟล์ของเกมนั้นจะถูกสร้างอัตโนมัติ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("เกม:", selection: $settings.currentGameID) {
                        ForEach(settings.gameProfiles.keys.sorted(), id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }

                    TextField("ชื่อเกม (ใช้ใน prompt):", text: Binding(
                        get: { settings.currentProfile.title },
                        set: { settings.currentProfile.title = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Text("ใส่ชื่อเกมจริง เช่น \"Final Fantasy XVI\" เพื่อให้ AI เลือกคำและน้ำเสียงให้เข้ากับเกม")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !settings.currentGameID.isEmpty {
                glossarySection
            }

            Section("บริบทบทสนทนา") {
                Toggle("ส่งบทพูดก่อนหน้าให้ AI ด้วย", isOn: $settings.useConversationContext)

                Text("ช่วยให้เรียกชื่อตัวละครและสรรพนามต่อเนื่องกัน ใช้ได้กับ OpenAI และ Claude (ใช้ token เพิ่มเล็กน้อย)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Glossary

    private var glossarySection: some View {
        Section {
            if settings.currentProfile.glossary.isEmpty {
                Text("ยังไม่มีคำ — เพิ่มชื่อตัวละคร สถานที่ หรือสกิล ที่อยากให้แปลแบบเดิมทุกครั้ง")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(settings.currentProfile.glossary) { entry in
                HStack(spacing: 6) {
                    TextField("คำต้นฉบับ", text: binding(for: entry.id, \.source))
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("คำแปลที่ต้องการ", text: binding(for: entry.id, \.target))
                        .textFieldStyle(.roundedBorder)
                    Button {
                        removeEntry(entry.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("ลบคำนี้")
                }
            }

            Button {
                var profile = settings.currentProfile
                profile.glossary.append(GlossaryEntry(source: "", target: ""))
                settings.currentProfile = profile
            } label: {
                Label("เพิ่มคำ", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Glossary — \(settings.currentProfile.title)")
        } footer: {
            Text("OpenAI/Claude จะใช้คำแปลนี้ในประโยค · ทุก provider: ถ้าข้อความบนจอตรงกับคำนี้ทั้งคำ จะใช้คำแปลนี้ทันทีโดยไม่เรียก API")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for id: UUID, _ keyPath: WritableKeyPath<GlossaryEntry, String>) -> Binding<String> {
        Binding(
            get: {
                settings.currentProfile.glossary.first(where: { $0.id == id })?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                var profile = settings.currentProfile
                guard let index = profile.glossary.firstIndex(where: { $0.id == id }) else { return }
                profile.glossary[index][keyPath: keyPath] = newValue
                settings.currentProfile = profile
            }
        )
    }

    private func removeEntry(_ id: UUID) {
        var profile = settings.currentProfile
        profile.glossary.removeAll { $0.id == id }
        settings.currentProfile = profile
    }
}
