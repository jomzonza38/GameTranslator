import AppKit
import CoreGraphics

/// Application delegate — sets up the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    /// Set while waiting for the user to grant Screen Recording. When macOS relaunches
    /// the app afterwards ("Quit & Reopen"), the window picker opens so it's obvious
    /// the app is running — a menu bar app otherwise shows only a small icon.
    private let awaitingPermissionKey = "awaitingScreenRecordingPermission"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host — skip the menu bar UI, permission
        // prompts and the single-instance check so tests run unattended.
        let environment = ProcessInfo.processInfo.environment
        if environment.keys.contains(where: { $0.hasPrefix("XCTest") }) || NSClassFromString("XCTestCase") != nil {
            return
        }

        // Only one copy should run (two copies fight over the menu bar item and log).
        guard waitForOtherInstancesToExit() else {
            NSApp.terminate(nil)
            return
        }

        GameLog.setup()
        GameLog.log("=== GameTranslator Started (v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")) ===")
        GameLog.log("Running from: \(Bundle.main.bundlePath)")

        // Menu bar icon + pipeline
        statusBarController = StatusBarController()

        // No Dock icon, just the menu bar
        NSApp.setActivationPolicy(.accessory)

        checkScreenRecordingPermission()

        GameLog.log("App ready, menu bar icon active")
    }

    /// "Quit & Reopen" in System Settings launches the new copy while the old one may
    /// still be shutting down. Previously the new copy saw the old one and quit itself,
    /// so the app seemed not to reopen. Wait up to 3 s before treating it as a duplicate.
    private func waitForOtherInstancesToExit() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(3)

        while true {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != myPID && !$0.isTerminated }
            if others.isEmpty { return true }
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    // MARK: - Permission Handling

    /// Uses CGPreflightScreenCaptureAccess, which never shows a system prompt.
    /// (The old code polled SCShareableContent every 3 s; on recent macOS each of
    /// those calls can pop the "record this screen" dialog again.)
    private func checkScreenRecordingPermission() {
        let defaults = UserDefaults.standard

        if CGPreflightScreenCaptureAccess() {
            GameLog.log("Screen Recording permission granted \u{2713}")
            if defaults.bool(forKey: awaitingPermissionKey) {
                defaults.removeObject(forKey: awaitingPermissionKey)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self?.statusBarController?.presentWindowPicker()
                }
            }
            return
        }

        GameLog.log("Screen Recording permission not granted — asking once")
        defaults.set(true, forKey: awaitingPermissionKey)
        showPermissionAlert()
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "ต้องอนุญาต Screen Recording"
        alert.informativeText = """
            1. กด "เปิด System Settings"
            2. เปิดสวิตช์ GameTranslator ใน Screen & System Audio Recording
            3. กด "ออกและเปิดใหม่" (Quit & Reopen) — แอปจะเปิดกลับมาพร้อมหน้าต่างเลือกเกม

            ถ้าเห็น GameTranslator หลายรายการ ให้ลบอันเก่าออก (ปุ่ม −) แล้วเปิดสวิตช์อันที่เหลือ
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "เปิด System Settings")
        alert.addButton(withTitle: "ทีหลัง")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Adds the app to the Screen Recording list (once per launch)
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            await statusBarController?.pipeline.stop()
        }
    }
}
