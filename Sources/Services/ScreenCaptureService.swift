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
    /// `capturedWindowSize` = the size (points) of the window ScreenCaptureKit captured
    /// (from the frame info; nil if unknown).
    func screenCaptureService(_ service: ScreenCaptureService, didCaptureFrame image: CGImage?, fingerprint: UInt64, contentRect: CGRect, capturedWindowSize: CGSize?)
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
///
/// Measured on the owner's Mac (T-0020, full-screen game): `SCStreamFrameInfo.contentRect`
/// is in output points (× `scaleFactor` = buffer pixels), and ScreenCaptureKit captures
/// the window at `contentRect.size / contentScale` points — for a full-screen window that
/// is ~122 pt taller than its CGWindowList bounds (the hidden title-bar area above the
/// screen), with the same left and bottom edges.
enum CaptureGeometry {
    /// Output pixels per window point (the stream is configured at 2× the window size)
    static let captureScale: CGFloat = 2

    struct PixelSize: Equatable {
        let width: Int
        let height: Int
    }

    /// Stream size for a window size (points)
    static func captureSize(forWindow size: CGSize) -> PixelSize {
        PixelSize(
            width: max(2, Int((size.width * captureScale).rounded())),
            height: max(2, Int((size.height * captureScale).rounded()))
        )
    }

    /// More than rounding noise apart
    static func differs(_ a: PixelSize, _ b: PixelSize) -> Bool {
        abs(a.width - b.width) > 2 || abs(a.height - b.height) > 2
    }

    /// The captured window's content inside the buffer, in buffer pixels:
    /// `contentRect × scaleFactor`. Nil (= use the whole buffer) when the frame info is
    /// missing or doesn't make sense for this buffer (no scaleFactor, doesn't fit, or
    /// implausibly small) — cropping to a wrong rect would silently lose text.
    static func contentPixelRect(contentRect: CGRect?, scaleFactor: CGFloat?, bufferSize: CGSize) -> CGRect? {
        guard let rect = contentRect, let scale = scaleFactor, scale > 0,
              rect.width > 0, rect.height > 0 else { return nil }
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let tolerance: CGFloat = 2
        guard pixels.minX >= -tolerance, pixels.minY >= -tolerance,
              pixels.maxX <= bufferSize.width + tolerance, pixels.maxY <= bufferSize.height + tolerance,
              pixels.width >= bufferSize.width * 0.25, pixels.height >= bufferSize.height * 0.25 else { return nil }
        return pixels.intersection(CGRect(origin: .zero, size: bufferSize)).integral
    }

    /// Whether the content is worth cropping to (it doesn't already fill the buffer)
    static func contentIsInset(_ content: CGRect, bufferSize: CGSize) -> Bool {
        content.minX > 2 || content.minY > 2
            || content.width < bufferSize.width - 4 || content.height < bufferSize.height - 4
    }

    /// Size of the window ScreenCaptureKit captured, in points: contentRect / contentScale
    static func capturedWindowSize(contentRect: CGRect?, contentScale: CGFloat?) -> CGSize? {
        guard let rect = contentRect, rect.width > 0, rect.height > 0 else { return nil }
        let scale = contentScale ?? 1
        guard scale > 0.05 else { return nil }
        return CGSize(width: rect.width / scale, height: rect.height / scale)
    }

    /// Where the captured window is on screen (CG coordinates): its size from the frame
    /// info, placed with the same left and bottom edges as the CGWindowList bounds.
    /// Without frame info, the CGWindowList bounds.
    static func mappingFrame(cgBounds: CGRect, capturedSize: CGSize?) -> CGRect {
        guard let size = capturedSize, size.width > 0, size.height > 0 else { return cgBounds }
        return CGRect(x: cgBounds.minX, y: cgBounds.maxY - size.height, width: size.width, height: size.height)
    }

    /// A rect normalized to `from` → normalized to `to` (both CG screen rects). Regions are
    /// drawn over the visible window (CGWindowList bounds) but OCR crops the captured image.
    static func convertNormalized(_ rect: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard to.width > 0, to.height > 0 else { return rect }
        let screen = screenRect(forContentBox: rect, windowFrame: from)
        return CGRect(
            x: (screen.minX - to.minX) / to.width,
            y: (screen.minY - to.minY) / to.height,
            width: screen.width / to.width,
            height: screen.height / to.height
        )
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

    /// Whether any of `rect` is on the visible part of the window (the captured window
    /// can reach above the screen, where nothing should be drawn)
    static func isVisible(_ rect: CGRect, within visible: CGRect) -> Bool {
        let overlap = rect.intersection(visible)
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }
}

/// Decides when to reconfigure the stream size. A new size must stay the same for
/// `settleTime` (full-screen transitions pass through several sizes), and at most
/// `maxResizes` happen per `period` — so the stream can never bounce between two sizes.
struct ResizeGovernor {
    var settleTime: TimeInterval = 0.5
    var period: TimeInterval = 10
    var maxResizes = 3

    private(set) var pendingTarget: CaptureGeometry.PixelSize?
    private var pendingSince: TimeInterval = 0
    private(set) var recentResizes: [TimeInterval] = []

    /// Whether to resize to `target` now (records the resize when true)
    mutating func shouldResize(to target: CaptureGeometry.PixelSize, configured: CaptureGeometry.PixelSize, now: TimeInterval) -> Bool {
        guard CaptureGeometry.differs(target, configured) else {
            pendingTarget = nil
            return false
        }
        if pendingTarget != target {
            pendingTarget = target
            pendingSince = now
            return false
        }
        guard now - pendingSince >= settleTime else { return false }
        recentResizes.removeAll { now - $0 >= period }
        guard recentResizes.count < maxResizes else { return false }
        recentResizes.append(now)
        pendingTarget = nil
        return true
    }

    /// Too many resizes recently — further ones are being held back
    func isHoldingBack(now: TimeInterval) -> Bool {
        recentResizes.filter { now - $0 < period }.count >= maxResizes
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
    /// Stream output size in pixels (kept equal to the captured window × 2, T-0020)
    private var configuredSize: CaptureGeometry.PixelSize?
    private var isResizing = false
    private var resizeGovernor = ResizeGovernor()
    private var loggedResizeHoldBack = false
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

        let output = StreamOutput { [weak self] image, fingerprint, capturedWindowSize in
            guard let self, self.sessionLock.withLock({ self.starts.isCurrent(generation) }) else { return }
            self.delegate?.screenCaptureService(
                self, didCaptureFrame: image, fingerprint: fingerprint,
                contentRect: window.frame, capturedWindowSize: capturedWindowSize
            )
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
            resizeGovernor = ResizeGovernor()
            loggedResizeHoldBack = false
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

    /// Keep the output sized to the captured window (× 2) so ScreenCaptureKit doesn't
    /// scale it down (contentScale 1). Called for every frame; `ResizeGovernor` decides.
    /// Uses the captured size from the frame info, falling back to the CGWindowList size
    /// — never both, so the two can't fight. Doesn't touch permissions.
    func requestResize(capturedWindowSize: CGSize?, cgWindowSize: CGSize?) {
        guard let windowSize = capturedWindowSize ?? cgWindowSize else { return }
        let target = CaptureGeometry.captureSize(forWindow: windowSize)
        let now = CFAbsoluteTimeGetCurrent()
        let claimed = sessionLock.withLock { () -> (SCStream, Double, CaptureGeometry.PixelSize)? in
            guard let stream, !isResizing, let configuredSize else { return nil }
            guard resizeGovernor.shouldResize(to: target, configured: configuredSize, now: now) else {
                if resizeGovernor.isHoldingBack(now: now), CaptureGeometry.differs(target, configuredSize), !loggedResizeHoldBack {
                    loggedResizeHoldBack = true
                    GameLog.log("Capture resize held back (too many in a short time); staying at \(configuredSize.width)x\(configuredSize.height)")
                }
                return nil
            }
            isResizing = true
            return (stream, frameRate, configuredSize)
        }
        guard let (stream, frameRate, old) = claimed else { return }

        Task {
            do {
                try await stream.updateConfiguration(Self.streamConfiguration(size: target, frameRate: frameRate))
                self.sessionLock.withLock {
                    self.configuredSize = target
                    self.isResizing = false
                }
                GameLog.log("Capture resized to the captured window: \(old.width)x\(old.height) → \(target.width)x\(target.height)")
            } catch {
                self.sessionLock.withLock { self.isResizing = false }
                GameLog.log("Capture resize failed (keeping the old size): \(error.localizedDescription)")
            }
        }
    }

    private static func streamConfiguration(size: CaptureGeometry.PixelSize, frameRate: Double) -> SCStreamConfiguration {
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
    /// (image, fingerprint, captured window size) — image is nil when the pixels equal
    /// the previous frame's
    private let onFrame: (CGImage?, UInt64, CGSize?) -> Void
    /// Captured window size of the last converted frame (reused for identical frames)
    private var lastCapturedWindowSize: CGSize?
    private var lastFrameTime: CFAbsoluteTime = 0
    private var lastFingerprint: UInt64?
    /// Fallback fingerprints for frames that couldn't be read (always "new")
    private var unreadableFrameCount: UInt64 = 0
    /// One context for the stream's lifetime — creating a CIContext per frame was the
    /// biggest CPU cost while capturing (T-0016). Only used on the capture queue.
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Last logged geometry, so the log only gets a line when it changes
    private var lastGeometryDescription: String?

    init(onFrame: @escaping (CGImage?, UInt64, CGSize?) -> Void) {
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
            onFrame(nil, fingerprint, lastCapturedWindowSize)
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
            contentRect: info.contentRect, scaleFactor: info.scaleFactor, bufferSize: bufferSize
        )
        // Captured window size only when the content rect was usable — otherwise the
        // image is the whole buffer and the CGWindowList bounds are the best guess
        let capturedWindowSize = content == nil ? nil
            : CaptureGeometry.capturedWindowSize(contentRect: info.contentRect, contentScale: info.contentScale)
        logGeometryIfChanged(bufferSize: bufferSize, info: info, content: content, capturedWindowSize: capturedWindowSize)
        if let content, CaptureGeometry.contentIsInset(content, bufferSize: bufferSize),
           let cropped = cgImage.cropping(to: content) {
            cgImage = cropped
        }

        lastFingerprint = fingerprint
        lastCapturedWindowSize = capturedWindowSize
        onFrame(cgImage, fingerprint, capturedWindowSize)
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
        content: CGRect?,
        capturedWindowSize: CGSize?
    ) {
        let description = "buffer=\(Int(bufferSize.width))x\(Int(bufferSize.height))"
            + " contentRect=\(info.contentRect.map(ScreenCaptureService.describe) ?? "nil")"
            + " contentScale=\(info.contentScale.map { String(format: "%.3f", $0) } ?? "nil")"
            + " scaleFactor=\(info.scaleFactor.map { String(format: "%.1f", $0) } ?? "nil")"
            + " → window content in buffer=\(content.map(ScreenCaptureService.describe) ?? "whole buffer (frame info unusable)")"
            + " captured window=\(capturedWindowSize.map { String(format: "%.0fx%.0f pt", $0.width, $0.height) } ?? "unknown")"
        guard description != lastGeometryDescription else { return }
        lastGeometryDescription = description
        GameLog.log("Capture frame geometry: \(description)")
    }
}
