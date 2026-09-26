import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreGraphics
import Carbon.HIToolbox

/// Controls the menu bar status item and its menu
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var learningWindow: NSWindow?
    private var welcomePopover: NSPopover?
    private var welcomeWindow: NSWindow?

    let pipeline = PipelineCoordinator()
    /// Capture card picture in a window on the Mac or on the TV (T-0027, T-0032)
    let tvOutput = TVOutputController()

    @Published var availableWindows: [SCWindow] = []
    @Published var selectedWindowTitle: String?

    override init() {
        super.init()
        setupStatusBar()
    }

    // MARK: - Status Bar Setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Game Translator")
            button.image?.size = NSSize(width: 18, height: 18)
            button.imagePosition = .imageLeft
        }

        // Rebuild menu whenever regions change (add/remove/clear)
        pipeline.onRegionsChanged = { [weak self] in
            self?.rebuildMenu()
        }

        // Game window closed while translating — show "not running" and the message
        pipeline.onStoppedUnexpectedly = { [weak self] in
            self?.selectedWindowTitle = nil
            self?.rebuildMenu()
            self?.updateStatusIcon(running: false)
        }

        // Capture card picture opened, closed or unplugged
        tvOutput.onChange = { [weak self] in
            guard let self else { return }
            self.rebuildMenu()
            self.updateStatusIcon(running: self.pipeline.isRunning || self.tvOutput.isActive)
        }

        rebuildMenu()
        registerHotKeys()
    }

    // MARK: - Global Hotkeys (⌃⌥ + key, so they don't clash with games or browsers)

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey
        let hotKeys = HotKeyManager.shared

        hotKeys.register(keyCode: kVK_ANSI_T, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.toggleTranslation() }
        }

        // ⌃⌥V open/close the capture card picture (T-0027, T-0032)
        hotKeys.register(keyCode: kVK_ANSI_V, modifiers: modifiers) { [weak self] in
            Task { @MainActor in self?.toggleTVOutput() }
        }

        // ⌃⌥1…9 show/hide region 1…9
        let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                          kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (index, keyCode) in numberKeys.enumerated() {
            hotKeys.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
                Task { @MainActor in self?.toggleRegion(at: index) }
            }
        }
    }

    /// Refill the menu (one NSMenu for the app's lifetime; see menuNeedsUpdate)
    func rebuildMenu() {
        let menu = self.menu ?? makeMenu()
        menu.removeAllItems()

        // Status
        let statusItem = NSMenuItem(title: "สถานะ: \(pipeline.status.displayName)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if tvOutput.isActive {
            addTVOutputInfo(to: menu)
        }

        if pipeline.isRunning {
            if let title = selectedWindowTitle {
                let windowItem = NSMenuItem(title: "🎮 \(title)", action: nil, keyEquivalent: "")
                windowItem.isEnabled = false
                menu.addItem(windowItem)
            }

            // Stats
            let stats = pipeline.stats
            if stats.totalFramesProcessed > 0 {
                let statsItem = NSMenuItem(
                    title: String(format: "⚡ OCR: %.0fms | แปล: %.0fms",
                                  stats.avgOCRTime * 1000,
                                  stats.avgTranslateTime * 1000),
                    action: nil,
                    keyEquivalent: ""
                )
                statsItem.isEnabled = false
                menu.addItem(statsItem)
            }
        }

        // Screen Recording not usable in this running copy yet
        if !ScreenRecordingPermission.isGranted {
            menu.addItem(NSMenuItem.separator())
            let permissionItem = NSMenuItem(
                title: "⚠️ ยังไม่ได้อนุญาต Screen Recording...",
                action: #selector(showPermissionInstructions),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)

            let relaunchItem = NSMenuItem(
                title: "🔄 เปิดแอปใหม่ (หลังอนุญาตแล้ว)",
                action: #selector(relaunchApp),
                keyEquivalent: ""
            )
            relaunchItem.target = self
            menu.addItem(relaunchItem)
        }

        // Error display
        if let error = pipeline.lastError {
            menu.addItem(NSMenuItem.separator())
            let errorItem = NSMenuItem(title: "⚠️ \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }
        if let error = tvOutput.lastError {
            if pipeline.lastError == nil { menu.addItem(NSMenuItem.separator()) }
            let errorItem = NSMenuItem(title: "⚠️ \(error)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        // Usage tracking
        if let remaining = AppSettings.shared.remainingCharacters {
            let usageItem = NSMenuItem(
                title: "📊 เหลือ: \(formatNumber(remaining)) ตัวอักษร",
                action: nil,
                keyEquivalent: ""
            )
            usageItem.isEnabled = false
            menu.addItem(usageItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Start/Stop
        if pipeline.isRunning {
            let stopItem = NSMenuItem(title: "⏹ หยุดแปล", action: #selector(stopTranslation), keyEquivalent: "t")
            stopItem.keyEquivalentModifierMask = [.control, .option]
            stopItem.target = self
            menu.addItem(stopItem)

            menu.addItem(NSMenuItem.separator())

            let settings = AppSettings.shared

            // --- Region List ---
            let regionHeaderTitle = settings.captureRegions.isEmpty
                ? "📍 พื้นที่แปล"
                : "📍 พื้นที่แปล (\(settings.captureRegions.count))"
            let regionHeaderItem = NSMenuItem(title: regionHeaderTitle, action: nil, keyEquivalent: "")
            regionHeaderItem.isEnabled = false
            menu.addItem(regionHeaderItem)

            for (index, region) in settings.captureRegions.enumerated() {
                let orderLabel = "\(index + 1)."
                let colorDot = colorCircle(for: region.color)
                let regionItem = NSMenuItem(
                    title: "   \(orderLabel) \(colorDot) \(region.name)\(region.isEnabled ? "" : "  (ซ่อน)")",
                    action: nil,
                    keyEquivalent: ""
                )
                regionItem.state = region.isEnabled ? .on : .off

                let subMenu = NSMenu()

                let toggleItem = NSMenuItem(
                    title: region.isEnabled ? "🙈 ซ่อนพื้นที่นี้" : "👁 แสดงพื้นที่นี้",
                    action: #selector(toggleRegionAction(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                toggleItem.keyEquivalentModifierMask = [.control, .option]
                toggleItem.target = self
                toggleItem.representedObject = region.id
                subMenu.addItem(toggleItem)

                subMenu.addItem(NSMenuItem.separator())

                // Move up (disabled if first)
                let moveUpItem = NSMenuItem(
                    title: "⬆ เลื่อนขึ้น",
                    action: index > 0 ? #selector(moveRegionUpAction(_:)) : nil,
                    keyEquivalent: ""
                )
                moveUpItem.target = self
                moveUpItem.representedObject = region.id
                subMenu.addItem(moveUpItem)

                // Move down (disabled if last)
                let moveDownItem = NSMenuItem(
                    title: "⬇ เลื่อนลง",
                    action: index < settings.captureRegions.count - 1 ? #selector(moveRegionDownAction(_:)) : nil,
                    keyEquivalent: ""
                )
                moveDownItem.target = self
                moveDownItem.representedObject = region.id
                subMenu.addItem(moveDownItem)

                subMenu.addItem(NSMenuItem.separator())

                let renameItem = NSMenuItem(
                    title: "✏️ เปลี่ยนชื่อ...",
                    action: #selector(renameRegionAction(_:)),
                    keyEquivalent: ""
                )
                renameItem.target = self
                renameItem.representedObject = region.id
                subMenu.addItem(renameItem)

                subMenu.addItem(NSMenuItem.separator())

                let removeItem = NSMenuItem(
                    title: "🗑 ลบพื้นที่นี้",
                    action: #selector(removeRegionAction(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = region.id
                subMenu.addItem(removeItem)

                regionItem.submenu = subMenu
                menu.addItem(regionItem)
            }

            // Add region button
            let addRegionItem = NSMenuItem(
                title: "   ➕ เพิ่มพื้นที่แปล...",
                action: #selector(addRegionAction),
                keyEquivalent: "r"
            )
            addRegionItem.keyEquivalentModifierMask = [.command, .shift]
            addRegionItem.target = self
            menu.addItem(addRegionItem)

            if !settings.captureRegions.isEmpty {
                let clearItem = NSMenuItem(
                    title: "   ❌ ลบทั้งหมด",
                    action: #selector(clearAllRegionsAction),
                    keyEquivalent: ""
                )
                clearItem.target = self
                menu.addItem(clearItem)
            }

            menu.addItem(NSMenuItem.separator())

            // --- Full Screen Mode ---
            let fullScreenItem = NSMenuItem(
                title: "🖥 แปลทั้งหน้าจอ",
                action: settings.captureRegions.isEmpty ? nil : #selector(clearAllRegionsAction),
                keyEquivalent: ""
            )
            fullScreenItem.target = self
            fullScreenItem.state = settings.captureRegions.isEmpty ? .on : .off
            if settings.captureRegions.isEmpty {
                fullScreenItem.isEnabled = false
            }
            menu.addItem(fullScreenItem)
        } else if !tvOutput.isActive {
            let selectItem = NSMenuItem(title: "🎮 เลือก Window...", action: #selector(showWindowPicker), keyEquivalent: "t")
            selectItem.keyEquivalentModifierMask = [.control, .option]
            selectItem.target = self
            menu.addItem(selectItem)
        }

        // Capture card picture (T-0027, T-0032)
        let tvItem = tvOutput.isActive
            ? NSMenuItem(title: "⏹ ปิดภาพ capture card", action: #selector(stopTVOutputAction), keyEquivalent: "v")
            : NSMenuItem(title: "📺 เปิดภาพ Switch (capture card)", action: #selector(startTVOutputAction), keyEquivalent: "v")
        tvItem.keyEquivalentModifierMask = [.control, .option]
        tvItem.target = self
        menu.addItem(tvItem)

        menu.addItem(NSMenuItem.separator())

        // History
        let historyItem = NSMenuItem(title: "📜 ประวัติคำแปล...", action: #selector(openHistory), keyEquivalent: "l")
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        historyItem.target = self
        menu.addItem(historyItem)

        // Learning (T-0022)
        let learningItem = NSMenuItem(title: "📚 เรียนรู้คำศัพท์...", action: #selector(openLearning), keyEquivalent: "")
        learningItem.target = self
        menu.addItem(learningItem)

        // How to use
        let helpItem = NSMenuItem(title: "❓ วิธีใช้", action: #selector(showWelcomeAction), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        // Settings
        let settingsItem = NSMenuItem(title: "⚙️ ตั้งค่า...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "ออกจากโปรแกรม", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        self.menu = menu
        statusItem?.menu = menu
        return menu
    }

    // MARK: - Actions

    @objc private func showWindowPicker() {
        // Without permission, SCShareableContent makes macOS pop its own
        // "record this screen" dialog on every call — and our alert followed it,
        // so each click produced two dialogs. Check silently first and only show
        // our instructions. (A permission granted while the app is running only
        // takes effect after "Quit & Reopen", which the instructions say.)
        guard CGPreflightScreenCaptureAccess() else {
            GameLog.log("Window picker: no Screen Recording permission")
            ScreenRecordingPermission.showInstructions()
            return
        }

        Task { @MainActor in
            do {
                availableWindows = try await ScreenCaptureService.availableWindows()

                let pickerWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                pickerWindow.title = "เลือก Game Window"
                pickerWindow.center()
                pickerWindow.isReleasedWhenClosed = false

                let pickerView = WindowPickerView(
                    windows: availableWindows,
                    onSelect: { [weak self] window in
                        pickerWindow.close()
                        self?.startTranslation(window: window)
                    }
                )
                pickerWindow.contentView = NSHostingView(rootView: pickerView)
                pickerWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                // SCShareableContent fails when Screen Recording permission
                // is not granted — show a helpful message without re-triggering
                // the system permission dialog
                GameLog.log("Cannot list windows: \(error.localizedDescription)")
                if !CGPreflightScreenCaptureAccess() {
                    ScreenRecordingPermission.showInstructions()
                } else {
                    self.showAlert(title: "ไม่สามารถดึงรายการ Window ได้", message: error.localizedDescription)
                }
            }
        }
    }

    private func startTranslation(window: SCWindow) {
        Task {
            // One session at a time: picking a game window ends TV Output
            tvOutput.stop()
            do {
                selectedWindowTitle = window.title ?? "Unknown"
                try await pipeline.start(window: window)
                rebuildMenu()
                // start() returns without error when it was stopped while starting
                updateStatusIcon(running: pipeline.isRunning)
            } catch {
                showAlert(title: "เริ่มจับภาพไม่ได้", message: error.localizedDescription)
            }
        }
    }

    // MARK: - Welcome

    @objc private func showPermissionInstructions() {
        ScreenRecordingPermission.showInstructions()
    }

    @objc private func relaunchApp() {
        ScreenRecordingPermission.relaunch()
    }

    @objc private func showWelcomeAction() {
        showWelcome()
    }

    /// Tell the user the app is running and where to find it. Points at the menu bar
    /// icon when it's visible; otherwise (hidden behind the notch or by a full-screen
    /// app) shows a small window near the top of the screen.
    func showWelcome() {
        dismissWelcome()

        let view = WelcomeView(
            onPickGame: { [weak self] in
                self?.dismissWelcome()
                self?.presentWindowPicker()
            },
            onOpenSettings: { [weak self] in
                self?.dismissWelcome()
                self?.openSettings()
            },
            onClose: { [weak self] in
                self?.dismissWelcome()
            }
        )

        NSApp.activate(ignoringOtherApps: true)

        if let button = statusItem?.button, isOnScreen(button) {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: view)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            welcomePopover = popover
            return
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Game Translator"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 420, height: 300))
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(
                x: visible.maxX - window.frame.width - 20,
                y: visible.maxY - 10
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        welcomeWindow = window
    }

    private func dismissWelcome() {
        welcomePopover?.performClose(nil)
        welcomePopover = nil
        welcomeWindow?.close()
        welcomeWindow = nil
    }

    /// Whether the status item button is actually visible on a screen
    private func isOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window, window.isVisible, window.occlusionState.contains(.visible) else {
            return false
        }
        return NSScreen.screens.contains { $0.frame.intersects(window.frame) }
    }

    /// Open the window picker (used after Screen Recording was just granted)
    func presentWindowPicker() {
        guard !pipeline.isRunning else { return }
        showWindowPicker()
    }

    /// ⌃⌥T — start (window picker) or stop; also stops TV Output when that is running
    private func toggleTranslation() {
        if tvOutput.isActive {
            tvOutput.stop()
        } else if pipeline.isRunning {
            stopTranslation()
        } else {
            showWindowPicker()
        }
    }

    @objc private func stopTranslation() {
        Task {
            await pipeline.stop()
            selectedWindowTitle = nil
            rebuildMenu()
            updateStatusIcon(running: false)
        }
    }

    // MARK: - Capture card picture (T-0027, T-0032)

    /// ⌃⌥V — open or close the capture card picture. Window translation is stopped first.
    private func toggleTVOutput() {
        if tvOutput.isActive {
            tvOutput.stop()
        } else {
            startTVOutput()
        }
    }

    @objc private func startTVOutputAction() {
        startTVOutput()
    }

    @objc private func stopTVOutputAction() {
        tvOutput.stop()
    }

    private func startTVOutput() {
        Task {
            if pipeline.isRunning {
                await pipeline.stop()
                selectedWindowTitle = nil
                rebuildMenu()
            }
            if let error = await tvOutput.start() {
                NSApp.activate(ignoringOtherApps: true)
                showAlert(title: "เปิดภาพ capture card ไม่ได้", message: error)
            }
        }
    }

    /// Card, format, display and sound lines while the capture card picture is open
    private func addTVOutputInfo(to menu: NSMenu) {
        var lines: [String]
        if let info = tvOutput.info {
            lines = ["📺 Capture card: \(info.deviceName)", "     \(info.formatDescription)"]
            lines.append("     🖥 " + (tvOutput.displayName.map { "จอ: \($0)" } ?? "หน้าต่างบน Mac"))
            lines.append("     " + (tvOutput.soundDescription ?? "🔈 กำลังเปิดเสียง…"))
        } else {
            lines = ["📺 กำลังเปิดภาพ capture card…"]
        }
        for line in lines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Game Translator — ตั้งค่า"
            window.center()
            window.isReleasedWhenClosed = false

            let settingsView = SettingsWindow(pipeline: pipeline)
            window.contentView = NSHostingView(rootView: settingsView)

            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openHistory() {
        if historyWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Game Translator — ประวัติคำแปล"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView())
            historyWindow = window
        }

        historyWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// One Learning window; reopening brings it to the front (T-0022)
    @objc private func openLearning() {
        if learningWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Game Translator — เรียนรู้คำศัพท์"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LearningView())
            learningWindow = window
        }

        learningWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Multi-Region Actions

    @objc private func addRegionAction() {
        let settings = AppSettings.shared
        let color = settings.nextRegionColor
        let name = settings.nextRegionName
        pipeline.addCaptureRegion(name: name, color: color)
    }

    @objc private func toggleRegionAction(_ sender: NSMenuItem) {
        guard let regionId = sender.representedObject as? UUID else { return }
        pipeline.toggleCaptureRegion(id: regionId)
    }

    /// ⌃⌥1…9 — show/hide region N
    private func toggleRegion(at index: Int) {
        let regions = AppSettings.shared.captureRegions
        guard regions.indices.contains(index) else { return }
        pipeline.toggleCaptureRegion(id: regions[index].id)
    }

    @objc private func moveRegionUpAction(_ sender: NSMenuItem) {
        guard let regionId = sender.representedObject as? UUID else { return }
        AppSettings.shared.moveRegion(id: regionId, direction: -1)
        rebuildMenu()
    }

    @objc private func moveRegionDownAction(_ sender: NSMenuItem) {
        guard let regionId = sender.representedObject as? UUID else { return }
        AppSettings.shared.moveRegion(id: regionId, direction: 1)
        rebuildMenu()
    }

    @objc private func removeRegionAction(_ sender: NSMenuItem) {
        guard let regionId = sender.representedObject as? UUID else { return }
        pipeline.removeCaptureRegion(id: regionId)
    }

    @objc private func clearAllRegionsAction() {
        pipeline.clearAllCaptureRegions()
    }

    @objc private func renameRegionAction(_ sender: NSMenuItem) {
        guard let regionId = sender.representedObject as? UUID else { return }
        let settings = AppSettings.shared
        guard let region = settings.captureRegions.first(where: { $0.id == regionId }) else { return }

        let alert = NSAlert()
        alert.messageText = "เปลี่ยนชื่อพื้นที่"
        alert.informativeText = "ใส่ชื่อใหม่สำหรับ \"\(region.name)\""
        alert.addButton(withTitle: "ตกลง")
        alert.addButton(withTitle: "ยกเลิก")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = region.name
        input.placeholderString = "ชื่อพื้นที่"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            if !newName.isEmpty {
                settings.renameRegion(id: regionId, to: newName)
                rebuildMenu()
            }
        }
    }

    @objc private func quitApp() {
        tvOutput.stop()
        Task {
            await pipeline.stop()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    private func updateStatusIcon(running: Bool) {
        if let button = statusItem?.button {
            let symbolName = running ? "character.bubble.fill" : "character.bubble"
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Game Translator")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ตกลง")
        alert.runModal()
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    /// Returns a colored circle emoji-like string for menu display
    private func colorCircle(for color: RegionColor) -> String {
        switch color {
        case .blue:   return "🔵"
        case .green:  return "🟢"
        case .orange: return "🟠"
        case .purple: return "🟣"
        case .pink:   return "🩷"
        case .yellow: return "🟡"
        case .cyan:   return "🔵"
        case .red:    return "🔴"
        }
    }
}

// MARK: - NSMenuDelegate

extension StatusBarController: NSMenuDelegate {
    /// Refill the menu each time it opens, so status, the latest error, stats and
    /// DeepL usage are current — without rebuilding it for every captured frame
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}
