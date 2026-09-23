import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreMedia

/// Why capture ended without the app asking for it
enum CaptureStopReason {
    /// The captured window no longer exists (game quit, crashed or restarted)
    case windowClosed
    /// ScreenCaptureKit stopped the stream with an error while the window still exists
    case streamFailed(Error)
}

/// Delegate to receive captured frames
protocol ScreenCaptureDelegate: AnyObject {
    func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage, contentRect: CGRect)
    /// Capture ended on its own — not through stopCapture(). Called at most once per session.
    func screenCaptureService(_ service: ScreenCaptureService, didStopUnexpectedly reason: CaptureStopReason)
}

/// Decides when the captured window is really gone. A single failed lookup may be a
/// glitch, so it takes `threshold` misses in a row.
struct WindowGoneDetector {
    var threshold = 2
    private(set) var misses = 0

    /// Record one check; returns true once the window has been missing `threshold` times in a row
    mutating func record(windowExists: Bool) -> Bool {
        misses = windowExists ? 0 : misses + 1
        return misses >= threshold
    }
}

/// Service that captures frames from a selected window using ScreenCaptureKit
final class ScreenCaptureService: NSObject, @unchecked Sendable {
    weak var delegate: ScreenCaptureDelegate?

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var selectedWindow: SCWindow?
    private var isCapturing = false
    private let captureQueue = DispatchQueue(label: "com.worawalan.GameTranslator.capture", qos: .userInitiated)

    /// The running stream and its window. Cleared by stopCapture() before the stream
    /// is stopped, so callbacks from our own stop (or an old stream) are ignored.
    /// Guarded by `sessionLock` — read from the capture queue and SCStream's delegate queue.
    private struct ActiveSession {
        let streamID: ObjectIdentifier
        let windowID: CGWindowID
    }
    private var activeSession: ActiveSession?
    private var watchdogTimer: DispatchSourceTimer?
    private let sessionLock = NSLock()

    /// Get list of available windows for capture
    /// Bundle identifiers of system UI that owns full-screen or decorative windows.
    /// These show up in SCShareableContent but are never something the user wants to
    /// translate, and picking one (the Dock's wallpaper window in particular) produces
    /// a capture that never delivers a second frame.
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent"
    ]

    /// Window titles used by system chrome that has no owning application.
    private static let excludedTitles: Set<String> = [
        "underbelly",
        "Wallpaper-",
        "Display 1 Backstop",
        "Backstop"
    ]

    static func availableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.filter { window in
            // Filter out system UI and tiny windows
            guard let title = window.title, !title.isEmpty else { return false }
            guard window.frame.width > 100 && window.frame.height > 100 else { return false }
            // Exclude our own app
            guard window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            // Exclude system UI (Dock, wallpaper, Notification Center, menu bar chrome)
            if let bundleID = window.owningApplication?.bundleIdentifier,
               excludedBundleIDs.contains(bundleID) {
                return false
            }
            // Windows with no owning app are system chrome (backstop, wallpaper, menu bar)
            guard window.owningApplication != nil else { return false }
            if excludedTitles.contains(title) || title.hasPrefix("Wallpaper") || title.hasSuffix("Backstop") {
                return false
            }
            return true
        }
    }

    /// Start capturing the selected window
    func startCapture(window: SCWindow, frameRate: Double = 5.0) async throws {
        guard !isCapturing else { return }

        selectedWindow = window

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2  // Retina
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // The delegate hears when ScreenCaptureKit stops the stream on its own
        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        let output = StreamOutput { [weak self] image in
            guard let self = self, let window = self.selectedWindow else { return }
            self.delegate?.screenCaptureService(self, didCaptureFrame: image, contentRect: window.frame)
        }
        self.streamOutput = output

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        self.stream = stream
        self.isCapturing = true

        let session = ActiveSession(streamID: ObjectIdentifier(stream), windowID: window.windowID)
        sessionLock.withLock { activeSession = session }
        startWatchdog(for: session)
    }

    /// Stop capturing
    func stopCapture() async {
        guard isCapturing else { return }

        // Forget the session first: this stop is ours and must not be reported
        endSession()
        try? await stream?.stopCapture()
        stream = nil
        streamOutput = nil
        selectedWindow = nil
        isCapturing = false
    }

    /// Update capture frame rate
    func updateFrameRate(_ frameRate: Double) async throws {
        guard let stream = stream, let window = selectedWindow else { return }

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        try await stream.updateConfiguration(config)
    }

    // MARK: - Unexpected stop

    /// Check once a second that the captured window still exists. ScreenCaptureKit
    /// doesn't reliably report a closed window: capture can even start on a window
    /// whose app already quit and then deliver no frames.
    private func startWatchdog(for session: ActiveSession) {
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        var detector = WindowGoneDetector()
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            if detector.record(windowExists: Self.windowExists(session.windowID)) {
                GameLog.log("Captured window \(session.windowID) no longer exists")
                self?.reportUnexpectedStop(of: session, reason: .windowClosed)
            }
        }
        sessionLock.withLock { watchdogTimer = timer }
        timer.resume()
    }

    /// Forget the active session and stop the watchdog
    private func endSession() {
        let timer = sessionLock.withLock { () -> DispatchSourceTimer? in
            activeSession = nil
            defer { watchdogTimer = nil }
            return watchdogTimer
        }
        timer?.cancel()
    }

    /// Tell the delegate once, and only if `session` is still the running one
    /// (the watchdog and didStopWithError can fire at the same moment)
    private func reportUnexpectedStop(of session: ActiveSession, reason: CaptureStopReason) {
        // Check and clear in one step so only the first caller reports
        var timer: DispatchSourceTimer?
        let isFirst = sessionLock.withLock { () -> Bool in
            guard activeSession?.streamID == session.streamID else { return false }
            activeSession = nil
            timer = watchdogTimer
            watchdogTimer = nil
            return true
        }
        guard isFirst else { return }
        timer?.cancel()
        delegate?.screenCaptureService(self, didStopUnexpectedly: reason)
    }

    /// Whether a window with this ID still exists (on screen or not). An API error
    /// counts as "exists" so a glitch never stops a working session.
    /// CGWindowList doesn't show the Screen Recording dialog.
    private static func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else {
            return true
        }
        return !list.isEmpty
    }

    /// Get the current game window frame
    var currentWindowFrame: CGRect? {
        guard let windowID = selectedWindow?.windowID else { return nil }

        let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
        guard let windowInfo = windowList?.first,
              let bounds = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }

        return CGRect(
            x: bounds["X"] ?? 0,
            y: bounds["Y"] ?? 0,
            width: bounds["Width"] ?? 0,
            height: bounds["Height"] ?? 0
        )
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let session = sessionLock.withLock { activeSession }
        guard let session, session.streamID == ObjectIdentifier(stream) else { return }
        GameLog.log("Capture stream stopped: \(error.localizedDescription)")
        let reason: CaptureStopReason = Self.windowExists(session.windowID) ? .streamFailed(error) : .windowClosed
        reportUnexpectedStop(of: session, reason: reason)
    }
}

// MARK: - Stream Output Handler

private final class StreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: (CGImage) -> Void
    private var lastFrameTime: CFAbsoluteTime = 0

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Skip frames that arrive too close together
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime > 0.05 else { return } // Min 50ms between frames
        lastFrameTime = now

        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        onFrame(cgImage)
    }
}
