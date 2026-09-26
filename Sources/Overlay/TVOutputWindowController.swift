import AppKit
import AVFoundation

// MARK: - Pure layout logic (unit-tested, T-0027 AC-1)

/// A display as the output-display choice sees it
struct TVDisplayCandidate: Equatable {
    let displayID: CGDirectDisplayID
    let isBuiltIn: Bool
    let isPrimary: Bool
}

enum TVOutputLayout {
    /// Index of the display to use as the TV: an external display, preferring one
    /// that isn't the primary (menu bar) display; nil if there is only the built-in one
    static func outputDisplayIndex(in displays: [TVDisplayCandidate]) -> Int? {
        let external = displays.indices.filter { !displays[$0].isBuiltIn }
        return external.first { !displays[$0].isPrimary } ?? external.first
    }

    /// The largest rect with `content`'s aspect ratio centred in `bounds`
    /// (letterbox / pillarbox on black)
    static func aspectFitRect(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Window

/// A borderless full-screen window on the TV that shows the capture card's picture
/// through `AVCaptureVideoPreviewLayer` (T-0027). It sits above the menu bar and Dock,
/// never becomes key or activates the app, and hides the cursor while it's over it
/// (best-effort: macOS may ignore cursor hiding while another app is active).
@MainActor
final class TVOutputWindowController {
    private var window: TVOutputPanel?
    private var pictureView: TVPictureView?

    /// The display the window is on, nil when closed
    private(set) var displayID: CGDirectDisplayID?

    var isShown: Bool { window != nil }

    /// Name of the TV for the menu
    var displayName: String? {
        guard let displayID else { return nil }
        return Self.screen(for: displayID)?.localizedName
    }

    // MARK: Display choice

    /// The screen to use as the TV (see `TVOutputLayout.outputDisplayIndex`)
    static func outputScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.enumerated().map { index, screen in
            let id = displayID(of: screen) ?? 0
            return TVDisplayCandidate(displayID: id, isBuiltIn: CGDisplayIsBuiltin(id) != 0, isPrimary: index == 0)
        }
        return TVOutputLayout.outputDisplayIndex(in: candidates).map { screens[$0] }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { Self.displayID(of: $0) == displayID }
    }

    // MARK: Show / close

    func show(on screen: NSScreen, session: AVCaptureSession, videoSize: CGSize) {
        close()

        let panel = TVOutputPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isMovable = false
        panel.animationBehavior = .none

        let view = TVPictureView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.attach(session: session, videoSize: videoSize)
        panel.contentView = view
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        window = panel
        pictureView = view
        displayID = Self.displayID(of: screen)
        view.hideCursorIfInside()
        GameLog.log("TV Output: window on \(screen.localizedName) \(Int(screen.frame.width))x\(Int(screen.frame.height))")
    }

    func close() {
        pictureView?.detach()
        window?.orderOut(nil)
        window?.close()
        window = nil
        pictureView = nil
        displayID = nil
    }

    /// Displays changed (plugged, unplugged, resolution). Returns false if the TV
    /// is gone; otherwise re-fits the window to the TV's current frame.
    func displaysChanged() -> Bool {
        guard let displayID, let window else { return true }
        guard let screen = Self.screen(for: displayID) else { return false }
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        return true
    }
}

/// Never key, never main: showing or clicking it doesn't take focus from the game
private final class TVOutputPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Black view holding the preview layer, aspect-fit to the view's bounds
private final class TVPictureView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoSize: CGSize = .zero
    private var cursorHidden = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { nil }

    func attach(session: AVCaptureSession, videoSize: CGSize) {
        self.videoSize = videoSize
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        preview.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(preview)
        previewLayer = preview
        needsLayout = true
    }

    func detach() {
        previewLayer?.session = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        showCursor()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = TVOutputLayout.aspectFitRect(content: videoSize, in: bounds)
        CATransaction.commit()
    }

    // Cursor hiding while over the TV

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hideCursor() }
    override func mouseExited(with event: NSEvent) { showCursor() }

    func hideCursorIfInside() {
        guard let window else { return }
        if window.frame.contains(NSEvent.mouseLocation) { hideCursor() }
    }

    private func hideCursor() {
        guard !cursorHidden else { return }
        NSCursor.hide()
        cursorHidden = true
    }

    private func showCursor() {
        guard cursorHidden else { return }
        NSCursor.unhide()
        cursorHidden = false
    }
}
