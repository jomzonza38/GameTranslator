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

            Section("บริบทบทสนทนา") {
                Toggle("ส่งบทพูดก่อนหน้าให้ AI ด้วย", isOn: $settings.useConversationContext)

                Text("ช่วยให้เรียกชื่อตัวละครและสรรพนามต่อเนื่องกัน ใช้ได้กับ OpenAI และ Claude (ใช้ token เพิ่มเล็กน้อย)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
