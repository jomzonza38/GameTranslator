import AppKit
import CoreGraphics

/// Application delegate — sets up the menu bar app
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    /// Set while waiting for the user to grant Screen Recording. When macOS relaunches
    /// the app afterwards ("Quit & Reopen"), the welcome message is shown even if it
    /// was turned off, so it's obvious the app is running.
    private let awaitingPermissionKey = "awaitingScreenRecordingPermission"

    /// Sent by a second copy of the app to the one already running
    static let showWelcomeNotification = Notification.Name("com.worawalan.GameTranslator.showWelcome")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host — skip the menu bar UI, permission
        // prompts and the single-instance check so tests run unattended.
        let environment = ProcessInfo.processInfo.environment
        if environment.keys.contains(where: { $0.hasPrefix("XCTest") }) || NSClassFromString("XCTestCase") != nil {
            return
        }

        // Only one copy should run (two copies fight over the menu bar item and log).
        guard waitForOtherInstancesToExit() else {
            // Opening the app while a copy is still running used to quit silently,
            // which looked like the app did nothing. Ask the running copy to show
            // its welcome message instead, then quit this one.
            GameLog.log("Another copy is still running — asking it to show itself, quitting this one")
            DistributedNotificationCenter.default().postNotificationName(
                Self.showWelcomeNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate()
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            forName: Self.showWelcomeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.statusBarController?.showWelcome()
            }
        }

        GameLog.setup()
        GameLog.log("=== GameTranslator Started (v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?")) ===")
        GameLog.log("Running from: \(Bundle.main.bundlePath)")

        // Menu bar icon + pipeline
        statusBarController = StatusBarController()

        // Let Vision prepare its OCR model now, in the background — the first
        // recognition can take about a minute (see OCRService.warmUp)
        let settings = AppSettings.shared
        OCRService.warmUp(
            recognitionLevel: settings.effectiveOCRAccuracy == .accurate ? .accurate : .fast,
            languages: settings.sourceLanguage.visionLanguages
        )

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
            let justGranted = defaults.bool(forKey: awaitingPermissionKey)
            defaults.removeObject(forKey: awaitingPermissionKey)

            Task { @MainActor [weak self] in
                // Give the menu bar item a moment to appear before pointing at it
                try? await Task.sleep(nanoseconds: 500_000_000)
                // Right after granting permission always show it (the user has just been
                // through System Settings and needs to know the app is back and where it is);
                // its "เลือกเกมเลย" button opens the window picker.
                if justGranted || AppSettings.shared.showWelcomeOnLaunch {
                    self?.statusBarController?.showWelcome()
                }
            }
            return
        }

        // Let macOS show its own "record this screen" dialog (it has an
        // "Open System Settings" button and adds the app to the list). Showing our
        // own alert first meant two dialogs in a row. If the user denied before,
        // macOS stays silent; picking a window then shows our instructions.
        defaults.set(true, forKey: awaitingPermissionKey)

        // Ask macOS at most once per installed build. Asking on every launch made the
        // dialog come back each time the app was opened before permission was given.
        // A new build (new code signature) needs its own request, hence the build key.
        let buildKey = ScreenRecordingPermission.currentBuildKey
        if defaults.string(forKey: "screenCaptureRequestedForBuild") != buildKey {
            defaults.set(buildKey, forKey: "screenCaptureRequestedForBuild")
            GameLog.log("Screen Recording permission not granted — requesting (build \(buildKey))")
            CGRequestScreenCaptureAccess()
        } else {
            GameLog.log("Screen Recording permission not granted — already asked for this build")
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.statusBarController?.showWelcome()
            }
        }
    }

    /// Opening the app again while it's already running (Finder, Spotlight, Launchpad)
    /// reaches the running copy — show where it is instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusBarController?.showWelcome()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Learning data (T-0022): its save is debounced — write what's pending now
        MainActor.assumeIsolated {
            LearningStore.shared.saveIfNeeded()
        }
        Task { @MainActor in
            await statusBarController?.pipeline.stop()
        }
    }
}
