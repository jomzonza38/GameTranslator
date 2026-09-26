import AppKit
import AVFoundation

// MARK: - Pure layout logic (unit-tested, T-0032 AC-1)

enum CaptureCardWindowLayout {
    /// Share of the screen's visible area a new window uses
    static let defaultScreenShare: CGFloat = 0.75

    /// Content size for a new window: the picture's aspect ratio, as large as fits in
    /// `defaultScreenShare` of the visible frame
    static func defaultContentSize(video: CGSize, visibleFrame: CGRect) -> CGSize {
        let area = CGRect(origin: .zero, size: CGSize(width: visibleFrame.width * defaultScreenShare,
                                                      height: visibleFrame.height * defaultScreenShare))
        return TVOutputLayout.aspectFitRect(content: video, in: area).size
    }

    /// `content` changed to the picture's aspect ratio, keeping its width (used when a
    /// saved window size came from a card format with another aspect ratio)
    static func keepingAspect(_ content: CGSize, video: CGSize) -> CGSize {
        guard video.width > 0, video.height > 0, content.width > 0 else { return content }
        return CGSize(width: content.width, height: (content.width * video.height / video.width).rounded())
    }
}

// MARK: - Window

/// The capture card's picture in a normal window on the Mac (T-0032): title bar,
/// resizable with the picture's aspect ratio, movable, remembers its frame, and can
/// go macOS full screen (green button / ⌃⌘F). The picture is drawn only by the
/// `AVCaptureVideoPreviewLayer` inside `TVPictureView`. The cursor hides over the
/// picture only in full screen. Closing the window (red button / ⌘W) calls `onClose`.
@MainActor
final class CaptureCardWindowController: NSObject, NSWindowDelegate {
    /// The user closed the window (not called for `close()`)
    var onClose: (() -> Void)?

    private var window: CaptureCardWindow?
    private var pictureView: TVPictureView?
    private var videoSize: CGSize = .zero
    private var isFullScreen = false

    private static let frameName = "CaptureCardWindow"

    var isShown: Bool { window != nil }

    func show(session: AVCaptureSession, videoSize: CGSize, title: String) {
        close()
        self.videoSize = videoSize

        let screen = Self.macScreen()
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let size = CaptureCardWindowLayout.defaultContentSize(video: videoSize, visibleFrame: visible)

        let window = CaptureCardWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.contentMinSize = CGSize(width: 320, height: 180)
        if videoSize.width > 0, videoSize.height > 0 {
            window.contentAspectRatio = videoSize
        }

        let view = TVPictureView(frame: CGRect(origin: .zero, size: size))
        view.hidesCursor = false
        view.attach(session: session, videoSize: videoSize)
        window.contentView = view

        // Same size/position as last time; otherwise centred on the Mac's own display
        if window.setFrameUsingName(Self.frameName) {
            let content = window.contentRect(forFrameRect: window.frame)
            let fixed = CaptureCardWindowLayout.keepingAspect(content.size, video: videoSize)
            if fixed != content.size {
                window.setContentSize(fixed)
            }
        } else if let screen {
            let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
            window.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - frame.width / 2,
                                          y: screen.visibleFrame.midY - frame.height / 2))
        }

        window.delegate = self
        self.window = window
        pictureView = view
        isFullScreen = false

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        GameLog.log("Capture card window: \(Int(window.frame.width))x\(Int(window.frame.height)) on \(window.screen?.localizedName ?? "?")")
    }

    /// Close without calling `onClose` (stop from the menu, hotkey or an unplug)
    func close() {
        guard let window else { return }
        window.delegate = nil
        pictureView?.detach()
        window.orderOut(nil)
        window.close()
        self.window = nil
        pictureView = nil
    }

    /// The Mac's built-in display (see `TVOutputLayout.macDisplayIndex`)
    static func macScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.enumerated().map { index, screen in
            let id = TVOutputWindowController.displayID(of: screen) ?? 0
            return TVDisplayCandidate(displayID: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0, isPrimary: index == 0)
        }
        return TVOutputLayout.macDisplayIndex(in: candidates).map { screens[$0] }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Red button / ⌘W: the controller stops capture and sound, then close() finds
        // no window (delegate already cleared below) and does nothing
        window?.delegate = nil
        pictureView?.detach()
        window = nil
        pictureView = nil
        onClose?()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isFullScreen = true
        pictureView?.hidesCursor = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isFullScreen = false
        pictureView?.hidesCursor = false
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    /// Only the window-mode frame is remembered, never the full-screen one
    private func saveFrame() {
        guard !isFullScreen, let window, !window.styleMask.contains(.fullScreen) else { return }
        window.saveFrame(usingName: Self.frameName)
    }
}

/// The app has no main menu (menu bar app), so the usual window shortcuts are
/// handled here: ⌃⌘F full screen, ⌘W close
private final class CaptureCardWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
        case ("f", [.control, .command]):
            toggleFullScreen(nil)
            return true
        case ("w", [.command]):
            performClose(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
