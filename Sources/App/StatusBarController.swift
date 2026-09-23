import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreGraphics

/// Controls the menu bar status item and its menu
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    let pipeline = PipelineCoordinator()

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

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Status
        let statusItem = NSMenuItem(title: "สถานะ: \(pipeline.status.displayName)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

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

        // Error display
        if let error = pipeline.lastError {
            menu.addItem(NSMenuItem.separator())
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
            stopItem.keyEquivalentModifierMask = [.command, .shift]
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
                    title: "   \(orderLabel) \(colorDot) \(region.name)",
                    action: nil,
                    keyEquivalent: ""
                )

                let subMenu = NSMenu()

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
        } else {
            let selectItem = NSMenuItem(title: "🎮 เลือก Window...", action: #selector(showWindowPicker), keyEquivalent: "t")
            selectItem.keyEquivalentModifierMask = [.command, .shift]
            selectItem.target = self
            menu.addItem(selectItem)
        }

        menu.addItem(NSMenuItem.separator())

        // History
        let historyItem = NSMenuItem(title: "📜 ประวัติคำแปล...", action: #selector(openHistory), keyEquivalent: "l")
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        historyItem.target = self
        menu.addItem(historyItem)

        // Settings
        let settingsItem = NSMenuItem(title: "⚙️ ตั้งค่า...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "ออกจากโปรแกรม", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.menu = menu
        self.statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func showWindowPicker() {
        // Try fetching windows directly via SCShareableContent.
        // CGPreflightScreenCaptureAccess() caches its result for the process
        // lifetime, so it returns false even after the user grants permission.
        // Calling CGRequestScreenCaptureAccess() again re-opens the system
        // dialog, creating an annoying loop. Instead, just try the real API
        // and show an informational alert only if it fails.
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
                    self.showAlert(
                        title: "ต้องอนุญาต Screen Recording",
                        message: "กรุณาเปิด System Settings → Privacy & Security → Screen & System Audio Recording แล้วเปิดสวิตช์ GameTranslator\n\nหลังเปิดแล้วกรุณาปิดแอปแล้วเปิดใหม่"
                    )
                } else {
                    self.showAlert(title: "ไม่สามารถดึงรายการ Window ได้", message: error.localizedDescription)
                }
            }
        }
    }

    private func startTranslation(window: SCWindow) {
        Task {
            do {
                selectedWindowTitle = window.title ?? "Unknown"
                try await pipeline.start(window: window)
                rebuildMenu()
                updateStatusIcon(running: true)
            } catch {
                showAlert(title: "เริ่มจับภาพไม่ได้", message: error.localizedDescription)
            }
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

    // MARK: - Multi-Region Actions

    @objc private func addRegionAction() {
        let settings = AppSettings.shared
        let color = settings.nextRegionColor
        let name = settings.nextRegionName
        pipeline.addCaptureRegion(name: name, color: color)
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
