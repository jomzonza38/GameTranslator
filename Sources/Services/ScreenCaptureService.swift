import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import zlib

/// Why capture ended without the app asking for it
enum CaptureStopReason {
    /// The captured window no longer exists (game quit, crashed or restarted)
    case windowClosed
    /// ScreenCaptureKit stopped the stream with an error while the window still exists
    case streamFailed(Error)
}

/// Delegate to receive captured frames
protocol ScreenCaptureDelegate: AnyObject {
    /// `image` is nil when the frame has exactly the same pixels as the previous one
    /// (ScreenCaptureKit keeps sending frames for a static window); `fingerprint`
    /// identifies the pixels either way.
    func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage?, fingerprint: UInt64, contentRect: CGRect)
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

/// How the captured buffer relates to the game window on screen (T-0020).
/// Pure functions — the mapping every overlay box, outline and region relies on.
enum CaptureGeometry {
    /// Output pixels per window point (the stream is configured at 2× the window size)
    static let captureScale: CGFloat = 2

    /// Stream size for a window size (points)
    static func captureSize(forWindow size: CGSize) -> (width: Int, height: Int) {
        (max(2, Int((size.width * captureScale).rounded())), max(2, Int((size.height * captureScale).rounded())))
    }

    /// Whether the stream must be reconfigured: the window's size no longer matches it,
    /// so ScreenCaptureKit would scale / pad the window inside the old buffer
    static func needsResize(configured: (width: Int, height: Int), window size: CGSize) -> Bool {
        let wanted = captureSize(forWindow: size)
        return abs(wanted.width - configured.width) > 2 || abs(wanted.height - configured.height) > 2
    }

    /// Where the window's content sits inside the output buffer, in buffer pixels, from
    /// the frame's `SCStreamFrameInfo`. Its units are not documented precisely, so the
    /// candidates (× contentScale × scaleFactor, × scaleFactor, as-is) are tried and the
    /// largest one that fits inside the buffer wins. Missing info → the whole buffer.
    static func contentPixelRect(contentRect: CGRect?, contentScale: CGFloat?, scaleFactor: CGFloat?, bufferSize: CGSize) -> CGRect {
        let full = CGRect(origin: .zero, size: bufferSize)
        guard let rect = contentRect, rect.width > 0, rect.height > 0 else { return full }
        let scale = scaleFactor ?? 1
        let candidates = [scale * (contentScale ?? 1), scale, 1]
            .map { CGRect(x: rect.minX * $0, y: rect.minY * $0, width: rect.width * $0, height: rect.height * $0) }
        let tolerance: CGFloat = 2
        let fitting = candidates.filter {
            $0.minX >= -tolerance && $0.minY >= -tolerance
                && $0.maxX <= bufferSize.width + tolerance && $0.maxY <= bufferSize.height + tolerance
        }
        guard let best = fitting.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return full }
        return best.intersection(full).integral
    }

    /// Whether the content is worth cropping to (it doesn't already fill the buffer)
    static func contentIsInset(_ content: CGRect, bufferSize: CGSize) -> Bool {
        content.minX > 2 || content.minY > 2
            || content.width < bufferSize.width - 4 || content.height < bufferSize.height - 4
    }

    /// A box normalized to the whole buffer → normalized to the window content in it
    static func boxInContent(_ box: CGRect, bufferSize: CGSize, content: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0 else { return box }
        return CGRect(
            x: (box.minX * bufferSize.width - content.minX) / content.width,
            y: (box.minY * bufferSize.height - content.minY) / content.height,
            width: box.width * bufferSize.width / content.width,
            height: box.height * bufferSize.height / content.height
        )
    }

    /// A box normalized to the window content → CG screen rect for the window frame
    static func screenRect(forContentBox box: CGRect, windowFrame: CGRect) -> CGRect {
        CGRect(
            x: windowFrame.minX + box.minX * windowFrame.width,
            y: windowFrame.minY + box.minY * windowFrame.height,
            width: box.width * windowFrame.width,
            height: box.height * windowFrame.height
        )
    }
}

/// Identifies a frame's pixels: CRC-32 and Adler-32 of every pixel row (row padding
/// excluded) plus the size. Exact — one changed pixel changes it — and cheap
/// (~1 ms for a 2880×1800 frame).
enum FrameFingerprint {
    static func of(_ pixelBuffer: CVPixelBuffer) -> UInt64? {
        guard !CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        return of(
            bytes: UnsafeRawPointer(base),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            bytesPerPixel: 4 // kCVPixelFormatType_32BGRA
        )
    }

    static func of(bytes: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, bytesPerPixel: Int) -> UInt64 {
        var crc = crc32(0, nil, 0)
        var adler = adler32(0, nil, 0)
        var size = [UInt32(truncatingIfNeeded: width), UInt32(truncatingIfNeeded: height)]
        size.withUnsafeMutableBytes { raw in
            let pointer = raw.baseAddress!.assumingMemoryBound(to: Bytef.self)
            crc = crc32(crc, pointer, uInt(raw.count))
        }
        let rowLength = uInt(width * bytesPerPixel)
        for row in 0..<height {
            let pointer = bytes.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Bytef.self)
            crc = crc32(crc, pointer, rowLength)
            adler = adler32(adler, pointer, rowLength)
        }
        return UInt64(crc & 0xFFFF_FFFF) << 32 | UInt64(adler & 0xFFFF_FFFF)
    }
}

/// Tells which start is the current one. Every new start and every stop moves it on,
/// so a start that is still awaiting (e.g. `SCStream.startCapture()`) can see
/// afterwards that it was stopped or replaced and must not keep its result.
struct StartGeneration {
    private(set) var current = 0

    /// Begin a new start; returns its token
    mutating func begin() -> Int {
        current += 1
        return current
    }

    /// A stop happened: every start still in flight is outdated
    mutating func invalidate() {
        current += 1
    }

    func isCurrent(_ token: Int) -> Bool {
        token == current
    }
}

/// Service that captures frames from a selected window using ScreenCaptureKit
final class ScreenCaptureService: NSObject, @unchecked Sendable {
    weak var delegate: ScreenCaptureDelegate?

    private let captureQueue = DispatchQueue(label: "com.worawalan.GameTranslator.capture", qos: .userInitiated)

    // Everything below is guarded by `sessionLock`: start and stop run concurrently
    // (a stop can arrive while a start is awaiting) and callbacks come from the
    // capture queue and SCStream's delegate queue.
    private let sessionLock = NSLock()
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var selectedWindow: SCWindow?
    private var starts = StartGeneration()

    /// The running stream and its window. Cleared by stopCapture() before the stream
    /// is stopped, so callbacks from our own stop (or an old stream) are ignored.
    private struct ActiveSession {
        let streamID: ObjectIdentifier
        let windowID: CGWindowID
    }
    private var activeSession: ActiveSession?
    private var watchdogTimer: DispatchSourceTimer?
    /// Stream output size in pixels (kept equal to the window size × 2, T-0020)
    private var configuredSize: (width: Int, height: Int)?
    private var isResizing = false
    private var frameRate: Double = 5

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

    /// Start capturing the selected window. Throws `CancellationError` if
    /// stopCapture() (or another start) ran while this start was in progress.
    func startCapture(window: SCWindow, frameRate: Double = 5.0) async throws {
        // Replace whatever is running — including a stream left by an interrupted
        // start — instead of skipping the new window and capturing the old one
        await stopCapture()
        let generation = sessionLock.withLock { starts.begin() }

        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Size the output to the window as it is now (SCWindow.frame is a snapshot
        // from when the window list was read)
        let liveBounds = Self.windowBounds(window.windowID)
        let size = CaptureGeometry.captureSize(forWindow: (liveBounds ?? window.frame).size)
        let config = Self.streamConfiguration(size: size, frameRate: frameRate)
        GameLog.log("Capture geometry at start: SCWindow.frame=\(Self.describe(window.frame)) live bounds=\(liveBounds.map(Self.describe) ?? "nil") output=\(size.width)x\(size.height)")

        // The delegate hears when ScreenCaptureKit stops the stream on its own
        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        let output = StreamOutput { [weak self] image, fingerprint in
            guard let self, self.sessionLock.withLock({ self.starts.isCurrent(generation) }) else { return }
            self.delegate?.screenCaptureService(self, didCaptureFrame: image, fingerprint: fingerprint, contentRect: window.frame)
        }

        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        // Keep the stream only if nothing stopped or replaced this start meanwhile.
        // The watchdog is running before the check so a stop right after it always
        // finds (and cancels) it.
        let session = ActiveSession(streamID: ObjectIdentifier(stream), windowID: window.windowID)
        let watchdog = makeWatchdog(for: session)
        let isCurrent = sessionLock.withLock { () -> Bool in
            guard starts.isCurrent(generation) else { return false }
            self.stream = stream
            self.streamOutput = output
            self.selectedWindow = window
            activeSession = session
            watchdogTimer = watchdog
            configuredSize = size
            self.frameRate = frameRate
            return true
        }
        guard isCurrent else {
            watchdog.cancel()
            GameLog.log("Capture start was stopped before it finished — discarding its stream")
            try? await stream.stopCapture()
            throw CancellationError()
        }
    }

    /// Stop capturing. Also cancels a start that is still in progress.
    func stopCapture() async {
        var timer: DispatchSourceTimer?
        let running = sessionLock.withLock { () -> SCStream? in
            starts.invalidate()
            // Forget the session before stopping: this stop is ours and must not be reported
            let running = stream
            stream = nil
            streamOutput = nil
            selectedWindow = nil
            activeSession = nil
            configuredSize = nil
            isResizing = false
            timer = watchdogTimer
            watchdogTimer = nil
            return running
        }
        timer?.cancel()
        try? await running?.stopCapture()
    }

    /// Update capture frame rate
    func updateFrameRate(_ frameRate: Double) async throws {
        let (stream, size) = sessionLock.withLock { (self.stream, configuredSize) }
        guard let stream, let size else { return }
        try await stream.updateConfiguration(Self.streamConfiguration(size: size, frameRate: frameRate))
        sessionLock.withLock { self.frameRate = frameRate }
    }

    /// Whether the stream's output size no longer matches `windowSize` (cheap, any thread)
    func captureNeedsResize(forWindowSize windowSize: CGSize) -> Bool {
        sessionLock.withLock {
            guard stream != nil, !isResizing, let configuredSize else { return false }
            return CaptureGeometry.needsResize(configured: configuredSize, window: windowSize)
        }
    }

    /// Follow a window resize / full-screen switch: reconfigure the output to the new
    /// window size so the window fills the buffer again (T-0020). A failure is logged
    /// and capture continues at the old size (frames are still mapped via their
    /// content rect). Doesn't touch permissions.
    func resizeCapture(toWindowSize windowSize: CGSize) async {
        let target = CaptureGeometry.captureSize(forWindow: windowSize)
        let claimed = sessionLock.withLock { () -> (SCStream, Double)? in
            guard let stream, !isResizing, let configuredSize,
                  CaptureGeometry.needsResize(configured: configuredSize, window: windowSize) else { return nil }
            isResizing = true
            return (stream, frameRate)
        }
        guard let (stream, frameRate) = claimed else { return }

        do {
            try await stream.updateConfiguration(Self.streamConfiguration(size: target, frameRate: frameRate))
            let old = sessionLock.withLock { () -> (width: Int, height: Int)? in
                defer { configuredSize = target; isResizing = false }
                return configuredSize
            }
            GameLog.log("Capture resized to follow the window: \(old.map { "\($0.width)x\($0.height)" } ?? "?") → \(target.width)x\(target.height)")
        } catch {
            sessionLock.withLock { isResizing = false }
            GameLog.log("Capture resize failed (keeping the old size): \(error.localizedDescription)")
        }
    }

    private static func streamConfiguration(size: (width: Int, height: Int), frameRate: Double) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 3
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        return config
    }

    static func describe(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }

    // MARK: - Unexpected stop

    /// A running timer that checks once a second that the captured window still
    /// exists. ScreenCaptureKit doesn't reliably report a closed window: capture can
    /// even start on a window whose app already quit and then deliver no frames.
    /// Reports are ignored unless `session` is still the active one.
    private func makeWatchdog(for session: ActiveSession) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: captureQueue)
        var detector = WindowGoneDetector()
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            if detector.record(windowExists: Self.windowExists(session.windowID)) {
                GameLog.log("Captured window \(session.windowID) no longer exists")
                self?.reportUnexpectedStop(of: session, reason: .windowClosed)
            }
        }
        timer.resume()
        return timer
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
        guard let windowID = sessionLock.withLock({ selectedWindow?.windowID }) else { return nil }
        return Self.windowBounds(windowID)
    }

    /// The window's current bounds in CG screen coordinates (CGWindowList; no dialog)
    private static func windowBounds(_ windowID: CGWindowID) -> CGRect? {
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
    /// (image, fingerprint) — image is nil when the pixels equal the previous frame's
    private let onFrame: (CGImage?, UInt64) -> Void
    private var lastFrameTime: CFAbsoluteTime = 0
    private var lastFingerprint: UInt64?
    /// Fallback fingerprints for frames that couldn't be read (always "new")
    private var unreadableFrameCount: UInt64 = 0
    /// One context for the stream's lifetime — creating a CIContext per frame was the
    /// biggest CPU cost while capturing (T-0016). Only used on the capture queue.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Last logged geometry, so the log only gets a line when it changes
    private var lastGeometryDescription: String?

    init(onFrame: @escaping (CGImage?, UInt64) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        // Skip frames that arrive too close together
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime > 0.05 else { return } // Min 50ms between frames
        lastFrameTime = now

        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let fingerprint: UInt64
        if let computed = FrameFingerprint.of(pixelBuffer) {
            fingerprint = computed
        } else {
            unreadableFrameCount += 1
            fingerprint = UInt64.max - unreadableFrameCount
        }

        // Same pixels as the previous frame: skip the image conversion
        if fingerprint == lastFingerprint {
            onFrame(nil, fingerprint)
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard var cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        // Keep only the window's content: if ScreenCaptureKit scaled or padded the
        // window inside the buffer (size changed since start), every normalized box
        // must be relative to the window, not to the buffer (T-0020)
        let bufferSize = CGSize(width: cgImage.width, height: cgImage.height)
        let info = Self.frameInfo(sampleBuffer)
        let content = CaptureGeometry.contentPixelRect(
            contentRect: info.contentRect, contentScale: info.contentScale,
            scaleFactor: info.scaleFactor, bufferSize: bufferSize
        )
        logGeometryIfChanged(bufferSize: bufferSize, info: info, content: content)
        if CaptureGeometry.contentIsInset(content, bufferSize: bufferSize),
           let cropped = cgImage.cropping(to: content) {
            cgImage = cropped
        }

        lastFingerprint = fingerprint
        onFrame(cgImage, fingerprint)
    }

    private static func frameInfo(_ sampleBuffer: CMSampleBuffer) -> (contentRect: CGRect?, contentScale: CGFloat?, scaleFactor: CGFloat?) {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else { return (nil, nil, nil) }
        var contentRect: CGRect?
        if let dictionary = attachments[.contentRect] as? NSDictionary {
            contentRect = CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        }
        let contentScale = (attachments[.contentScale] as? NSNumber).map { CGFloat($0.doubleValue) }
        let scaleFactor = (attachments[.scaleFactor] as? NSNumber).map { CGFloat($0.doubleValue) }
        return (contentRect, contentScale, scaleFactor)
    }

    private func logGeometryIfChanged(
        bufferSize: CGSize,
        info: (contentRect: CGRect?, contentScale: CGFloat?, scaleFactor: CGFloat?),
        content: CGRect
    ) {
        let description = "buffer=\(Int(bufferSize.width))x\(Int(bufferSize.height))"
            + " contentRect=\(info.contentRect.map(ScreenCaptureService.describe) ?? "nil")"
            + " contentScale=\(info.contentScale.map { String(format: "%.3f", $0) } ?? "nil")"
            + " scaleFactor=\(info.scaleFactor.map { String(format: "%.1f", $0) } ?? "nil")"
            + " → window content in buffer=\(ScreenCaptureService.describe(content))"
        guard description != lastGeometryDescription else { return }
        lastGeometryDescription = description
        GameLog.log("Capture frame geometry: \(description)")
    }
}
