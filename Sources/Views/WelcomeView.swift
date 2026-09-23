import SwiftUI

/// Shown when the app starts: a menu bar app has no window or Dock icon,
/// so without this people think it didn't open.
struct WelcomeView: View {
    @ObservedObject private var settings = AppSettings.shared
    let onPickGame: () -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !ScreenRecordingPermission.isGranted {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("ยังไม่ได้อนุญาต Screen Recording — เปิดสวิตช์ GameTranslator ใน System Settings แล้วกด \"เปิดแอปใหม่\" ในเมนูของแอป")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }

            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Translator พร้อมใช้งานแล้ว")
                        .font(.headline)
                    Text("แอปทำงานอยู่บนแถบเมนูด้านบนขวาของจอ")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                Text("มองหาไอคอนนี้บนแถบเมนู — แอปนี้ไม่มีหน้าต่างหลักและไม่มีไอคอนใน Dock")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                step(1, "คลิกไอคอน แล้วเลือก \"🎮 เลือก Window...\" หรือกด ⌃⌥T")
                step(2, "เลือกหน้าต่างเกม — คำแปลจะขึ้นบนจอทันที")
                step(3, "ตั้งค่า provider / API key ได้ที่เมนู ⚙️ ตั้งค่า")
            }

            Text("ไม่เห็นไอคอน? บน MacBook ที่มีรอยบาก ไอคอนอาจถูกบัง — กด ⌃⌥T แทนได้เลย")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Toggle("แสดงทุกครั้งที่เปิดแอป", isOn: $settings.showWelcomeOnLaunch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("ตั้งค่า") { onOpenSettings() }
                Button("ปิด") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("เลือกเกมเลย") { onPickGame() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
