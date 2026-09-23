import AppKit
import CoreGraphics

/// Controls the transparent overlay window that displays translated text
@MainActor
final class OverlayWindowController {
    private var overlayWindow: NSWindow?
    private var contentView: OverlayContentView?
    private var windowTrackingTimer: Timer?

    /// Show the overlay window positioned over the target window
    func show(over windowFrame: CGRect) {
        if overlayWindow == nil {
            createOverlayWindow()
        }

        guard let window = overlayWindow else { return }

        // Convert from CGWindow coordinates (origin top-left) to NSScreen (origin bottom-left)
        let screenFrame = convertToScreenCoordinates(windowFrame)
        window.setFrame(screenFrame, display: true)
        window.orderFrontRegardless()
    }

    /// Hide the overlay window
    func hide() {
        windowTrackingTimer?.invalidate()
        windowTrackingTimer = nil
        overlayWindow?.orderOut(nil)
        contentView?.clearRegions()
    }

    /// Hide the overlay window temporarily without clearing text regions.
    /// Used when showing the region selector so existing translations are preserved.
    func hideTemporarily() {
        overlayWindow?.orderOut(nil)
    }

    /// Update translated text regions on the overlay
    func updateRegions(_ regions: [TranslatedRegion], windowFrame: CGRect) {
        let screenFrame = convertToScreenCoordinates(windowFrame)
        overlayWindow?.setFrame(screenFrame, display: false)

        // Convert regions from absolute screen coordinates to overlay-relative coordinates
        let relativeRegions = regions.map { region -> TranslatedRegion in
            let relativeRect = CGRect(
                x: region.screenRect.origin.x - windowFrame.origin.x,
                y: region.screenRect.origin.y - windowFrame.origin.y,
                width: region.screenRect.width,
                height: region.screenRect.height
            )
            return region.withScreenRect(relativeRect)
        }

        contentView?.updateRegions(relativeRegions)
    }

    /// Update overlay position without changing text content (for window move tracking)
    func updatePosition(windowFrame: CGRect) {
        let screenFrame = convertToScreenCoordinates(windowFrame)
        overlayWindow?.setFrame(screenFrame, display: false)
    }

    // MARK: - Private

    private func createOverlayWindow() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Make it transparent and always on top
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // Don't show in mission control or app switcher
        window.hidesOnDeactivate = false

        let contentView = OverlayContentView(frame: .zero)
        window.contentView = contentView
        self.contentView = contentView

        self.overlayWindow = window
    }

    /// Convert from CGWindow coordinate system (origin at top-left of primary display)
    /// to NSScreen coordinate system (origin at bottom-left of primary display)
    private func convertToScreenCoordinates(_ cgRect: CGRect) -> CGRect {
        ScreenCoordinates.appKitRect(fromCG: cgRect)
    }
}
