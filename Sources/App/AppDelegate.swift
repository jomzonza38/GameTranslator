import AppKit
import CoreGraphics
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.worawalan.GameTranslator", category: "App")

/// Application delegate — sets up the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy should run. Xcode launches its own build right after the
        // install build phase has already launched the copy in /Applications; without
        // this guard both fight over the menu bar item and truncate each other's log.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            NSApp.terminate(nil)
            return
        }

        // Setup file logging
        GameLog.setup()
        GameLog.log("=== GameTranslator Started ===")
        GameLog.log("Running from: \(Bundle.main.bundlePath)")

        // Initialize the status bar controller (menu bar icon + pipeline)
        statusBarController = StatusBarController()

        // Set activation policy to accessory (no dock icon, just menu bar)
        NSApp.setActivationPolicy(.accessory)

        // Check Screen Recording permission
        // With ad-hoc signing, each rebuild creates a new code signature,
        // invalidating previous TCC grants. We avoid calling
        // CGRequestScreenCaptureAccess() every launch because it opens
        // System Settings as a dialog. Instead:
        //   • First-ever launch: call it once to register with TCC
        //   • Subsequent launches: check silently via SCShareableContent
        checkScreenRecordingPermission()

        GameLog.log("App ready, menu bar icon active")
    }

    // MARK: - Permission Handling

    private func checkScreenRecordingPermission() {
        let hasRegistered = UserDefaults.standard.bool(forKey: "hasRegisteredScreenCapture")

        if !hasRegistered {
            // First launch — register the app with TCC so it appears in
            // System Settings → Screen Recording list
            GameLog.log("First launch — registering with Screen Recording (TCC)...")
            CGRequestScreenCaptureAccess()
            UserDefaults.standard.set(true, forKey: "hasRegisteredScreenCapture")
            startPermissionMonitoring()
            return
        }

        // Subsequent launches — check silently without opening System Settings
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let windowCount = content.windows.count
                GameLog.log("Screen Recording permission granted \u{2713} (\(windowCount) windows)")
            } catch {
                GameLog.log("Screen Recording permission not granted: \(error.localizedDescription)")
                await MainActor.run {
                    self.showPermissionAlert()
                    self.startPermissionMonitoring()
                }
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "ต้องอนุญาต Screen Recording"
        alert.informativeText = "กรุณาเปิด System Settings → Privacy & Security → Screen & System Audio Recording\nแล้วเปิดสวิตช์ GameTranslator\n\nถ้าเห็น GameTranslator หลายตัว ให้ลบตัวเก่าออกแล้วเปิดตัวใหม่"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "เปิด System Settings")
        alert.addButton(withTitle: "ทีหลัง")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Monitor for Screen Recording permission using SCShareableContent
    private func startPermissionMonitoring() {
        GameLog.log("Starting permission monitoring (checking every 3s via SCShareableContent)...")
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task {
                do {
                    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                    let windowCount = content.windows.count
                    GameLog.log("Permission DETECTED via SCShareableContent! \(windowCount) windows \u{2713}")
                    self?.permissionCheckTimer?.invalidate()
                    self?.permissionCheckTimer = nil
                } catch {
                    GameLog.log("SCShareableContent check: \(error.localizedDescription) — still waiting...")
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionCheckTimer?.invalidate()
        Task { @MainActor in
            await statusBarController?.pipeline.stop()
        }
    }
}
