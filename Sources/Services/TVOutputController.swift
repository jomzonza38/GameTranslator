import AppKit
import AVFoundation

/// Capture card mode (T-0027, T-0032): the capture card's picture with its sound, in a
/// window on the Mac (default, `CaptureCardWindowController`) or full screen on an
/// external display (`TVOutputWindowController`, T-0027 — chosen in Settings from
/// T-0029). Owns the start/stop sequence, permissions and unplug handling; the
/// capture itself is `CaptureCardService`.
///
/// Off at every launch (nothing is persisted), so the Camera prompt only appears
/// when the user starts TV Output. Every start gets a new generation; a stop, an
/// unplug or a newer start makes older, still-running starts give up.
@MainActor
final class TVOutputController {
    enum State {
        case idle
        case starting
        case running
    }

    /// Where the picture is shown
    enum Output {
        /// A normal window on the Mac's own display (T-0032)
        case macWindow
        /// Borderless full screen on the first external display (T-0027)
        case externalDisplay
    }

    /// Mac window by default; T-0029 makes it a setting
    var output: Output = .macWindow

    private(set) var state: State = .idle
    /// Card, format and sound of the running session, for the menu
    private(set) var info: CaptureCardInfo?
    private(set) var soundDescription: String?
    /// Thai message for the menu after a failed start or an unexpected stop
    private(set) var lastError: String?

    var isActive: Bool { state != .idle }
    /// Name of the external display in use (nil in Mac window mode)
    var displayName: String? { window.displayName }

    /// The picture window on the Mac, to translate it with the window pipeline
    /// (T-0028). nil when not running or on an external display: there the picture
    /// panel sits above the translation overlay's level (Settings choice, T-0029).
    var translatableWindowNumber: Int? {
        guard state == .running, activeOutput == .macWindow else { return nil }
        return macWindow.windowNumber
    }

    /// Called on every state change (menu + status icon refresh)
    var onChange: (() -> Void)?

    private let capture = CaptureCardService()
    private let window = TVOutputWindowController()
    private let macWindow = CaptureCardWindowController()
    /// Output of the running (or starting) session
    private var activeOutput: Output = .macWindow
    private var generation = 0
    private var observers: [NSObjectProtocol] = []

    /// A start that hasn't finished after this long gives up (a card that hangs in
    /// startRunning() must not leave TV Output "starting" forever)
    private let startTimeout: UInt64 = 15_000_000_000

    // MARK: Start

    /// Start TV Output. Returns a Thai error message if it could not start (nil when
    /// it started, or was stopped while starting).
    @discardableResult
    func start() async -> String? {
        guard state == .idle else { return nil }
        generation += 1
        let current = generation
        activeOutput = output
        state = .starting
        info = nil
        soundDescription = nil
        lastError = nil
        observeDevicesAndDisplays()
        onChange?()
        GameLog.log("TV Output: starting")

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.startTimeout ?? 0)
            guard let self, self.generation == current, self.state == .starting else { return }
            GameLog.log("TV Output: ✗ start timed out")
            self.stop(reason: "capture card ไม่ตอบสนอง — ลองถอดแล้วเสียบใหม่ แล้วกด ⌃⌥V อีกครั้ง")
        }

        if activeOutput == .externalDisplay, TVOutputWindowController.outputScreen() == nil {
            return fail("ไม่พบจอที่สอง (ทีวี) — ต่อทีวีกับ Mac แล้วตั้งเป็น Extend (ไม่ใช่ Mirror) ใน System Settings → Displays", current)
        }

        guard await Self.requestAccess(for: .video) else {
            return fail(CaptureCardError.cameraDenied.localizedDescription, current)
        }
        guard generation == current else { return nil }

        let devices = CaptureCardService.videoDevices().map(CaptureCardService.candidate)
        GameLog.log("TV Output: video devices: \(devices.map(\.name))")
        guard let card = CaptureCardSelection.firstCaptureCard(in: devices) else {
            return fail(CaptureCardError.noDevice.localizedDescription, current)
        }

        let session: AVCaptureSession
        let cardInfo: CaptureCardInfo
        do {
            let started = try await capture.startVideo(deviceID: card.uniqueID, generation: current)
            session = started.0
            cardInfo = started.1
        } catch CaptureCardError.cancelled {
            return nil
        } catch {
            guard generation == current else { return nil }
            return fail(error.localizedDescription, current)
        }
        // Stopped (⌃⌥V, unplug, timeout) while the card was starting: that stop
        // already told the capture queue to stop this session
        guard generation == current else { return nil }

        switch activeOutput {
        case .macWindow:
            macWindow.onClose = { [weak self] in self?.stop() }
            macWindow.show(session: session, videoSize: cardInfo.videoSize,
                           title: "\(cardInfo.deviceName) — Game Translator")
        case .externalDisplay:
            // The TV may have been unplugged while the card was starting
            guard let screen = TVOutputWindowController.outputScreen() else {
                return fail("ทีวีถูกถอดออกระหว่างเริ่ม TV Output", current)
            }
            window.show(on: screen, session: session, videoSize: cardInfo.videoSize)
        }
        info = cardInfo
        state = .running
        onChange?()

        await startSound(cardName: cardInfo.deviceName, generation: current)
        return nil
    }

    /// Game sound (owner Q2): the card's own audio input, never the Mac's microphone.
    /// Without it the picture keeps running.
    private func startSound(cardName: String, generation current: Int) async {
        let audio = CaptureCardService.audioDevices().map(CaptureCardService.candidate)
        GameLog.log("TV Output: audio devices: \(audio.map(\.name))")
        guard let device = CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: cardName, in: audio) else {
            GameLog.log("TV Output: no audio input matching \(cardName) — picture only")
            setSound("🔇 ไม่พบเสียงของ capture card")
            return
        }
        guard await Self.requestAccess(for: .audio) else {
            guard generation == current else { return }
            GameLog.log("TV Output: microphone permission denied — picture only")
            setSound("🔇 ไม่มีเสียง — ยังไม่ได้อนุญาต Microphone (System Settings → Privacy & Security → Microphone)")
            return
        }
        guard generation == current else { return }
        let started = await capture.startAudio(deviceID: device.uniqueID, generation: current)
        guard generation == current else { return }
        setSound(started ? "🔈 เสียง: \(device.name)" : "🔇 เปิดเสียงของ capture card ไม่ได้")
    }

    private func setSound(_ text: String) {
        soundDescription = text
        onChange?()
    }

    private func fail(_ message: String, _ current: Int) -> String? {
        guard generation == current else { return nil }
        GameLog.log("TV Output: ✗ \(message)")
        stop(reason: message)
        return message
    }

    // MARK: Stop

    /// Stop TV Output (no-op when idle). `reason` is shown in the menu.
    func stop(reason: String? = nil) {
        guard state != .idle else { return }
        generation += 1
        capture.stop(generation: generation)
        window.close()
        macWindow.close()
        removeObservers()
        state = .idle
        info = nil
        soundDescription = nil
        lastError = reason
        GameLog.log("TV Output: stopped" + (reason.map { " — \($0)" } ?? ""))
        onChange?()
    }

    // MARK: Unplug handling

    private func observeDevicesAndDisplays() {
        removeObservers()
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let id = (note.object as? AVCaptureDevice)?.uniqueID
            let isVideo = (note.object as? AVCaptureDevice)?.hasMediaType(.video) ?? false
            MainActor.assumeIsolated { self?.deviceDisconnected(uniqueID: id, isVideo: isVideo) }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "unknown"
            MainActor.assumeIsolated { self?.captureFailed(message) }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureFailed("interrupted") }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func deviceDisconnected(uniqueID: String?, isVideo: Bool) {
        guard isActive else { return }
        // While starting the card isn't known yet: any video device leaving may be it
        let isOurCard = info.map { $0.deviceID == uniqueID } ?? isVideo
        guard isOurCard else { return }
        GameLog.log("TV Output: ✗ capture card disconnected")
        stop(reason: "ปิดภาพ capture card แล้ว เพราะ capture card ถูกถอดออก — เสียบกลับแล้วกด ⌃⌥V เพื่อเปิดใหม่")
    }

    /// Only this app's sessions post these; the window translation uses ScreenCaptureKit
    private func captureFailed(_ detail: String) {
        guard isActive else { return }
        GameLog.log("TV Output: ✗ capture session stopped: \(detail)")
        stop(reason: "ปิดภาพ capture card แล้ว เพราะ capture card หยุดส่งภาพ (\(detail)) — กด ⌃⌥V เพื่อเปิดใหม่")
    }

    /// Only the external display can go away; the Mac window doesn't care
    private func displaysChanged() {
        guard state == .running, activeOutput == .externalDisplay else { return }
        guard window.displaysChanged() else {
            GameLog.log("TV Output: ✗ TV disconnected")
            stop(reason: "หยุด TV Output แล้ว เพราะทีวีถูกถอดออก — ต่อทีวีกลับแล้วกด ⌃⌥V เพื่อเริ่มใหม่")
            return
        }
    }

    // MARK: Permissions

    /// Camera (the card) or Microphone (its sound). Asks only when macOS hasn't asked yet.
    private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }
}
