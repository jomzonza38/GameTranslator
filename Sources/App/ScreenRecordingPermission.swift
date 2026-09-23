import AppKit
import CoreGraphics

/// Screen Recording permission helpers
@MainActor
enum ScreenRecordingPermission {
    /// Identifies the installed build (path + executable modification date).
    /// Each rebuild gets a new code signature, which macOS treats as a new app.
    nonisolated static var currentBuildKey: String {
        let executable = Bundle.main.executableURL
        let modified = (executable.flatMap {
            try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
        })?.timeIntervalSince1970 ?? 0
        return "\(Bundle.main.bundlePath)#\(Int(modified))"
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Instructions for when the system dialog won't appear any more (the user
    /// already chose "Deny" once) — opens the Screen Recording settings page only.
    static func showInstructions() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "ต้องอนุญาต Screen Recording"
        alert.informativeText = """
            1. กด "เปิด System Settings"
            2. เปิดสวิตช์ GameTranslator ใน Screen & System Audio Recording
            3. กด "ออกและเปิดใหม่" (Quit & Reopen)

            ถ้าเห็น GameTranslator หลายรายการ ให้ลบอันเก่าออก (ปุ่ม −) แล้วเปิดสวิตช์อันที่เหลือ
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "เปิด System Settings")
        alert.addButton(withTitle: "ทีหลัง")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
