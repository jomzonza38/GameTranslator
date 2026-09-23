import AppKit
import CoreGraphics

/// Callback delivering the selected region in normalized coordinates (0...1)
/// relative to the game window.
typealias RegionSelectionHandler = (CGRect) -> Void

/// A transparent full-overlay window that lets the user drag a rectangle
/// to pick the area of the game window they want translated.
@MainActor
final class RegionSelectorWindow {
    private var window: NSWindow?
    private var selectorView: RegionSelectorView?

    /// Show the selector over the game window.
    /// `gameFrame` is in CG screen coordinates (top-left origin).
    /// `color` controls the selection border color for this region.
    func show(over gameFrame: CGRect, color: RegionColor = .blue, completion: @escaping RegionSelectionHandler) {
        // Convert CG (top-left) to NS (bottom-left)
        guard let mainScreen = NSScreen.main else { return }
        let screenHeight = mainScreen.frame.height
        let nsFrame = CGRect(
            x: gameFrame.origin.x,
            y: screenHeight - gameFrame.origin.y - gameFrame.height,
            width: gameFrame.width,
            height: gameFrame.height
        )

        let win = NSWindow(
            contentRect: nsFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        win.hasShadow = false
        win.level = .screenSaver // above everything
        win.ignoresMouseEvents = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = RegionSelectorView(frame: NSRect(origin: .zero, size: nsFrame.size))
        view.gameFrameSize = gameFrame.size
        view.regionColor = color
        view.onComplete = { [weak self] normalizedRect in
            self?.dismiss()
            completion(normalizedRect)
        }
        view.onCancel = { [weak self] in
            self?.dismiss()
        }

        win.contentView = view
        self.selectorView = view
        self.window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Set cursor to crosshair while selector is active
        NSCursor.crosshair.push()
    }

    func dismiss() {
        NSCursor.pop()
        window?.orderOut(nil)
        window = nil
        selectorView = nil
    }
}

// MARK: - Selector View

/// Custom NSView that tracks mouse drag to draw a selection rectangle.
private final class RegionSelectorView: NSView {
    var gameFrameSize: CGSize = .zero
    var regionColor: RegionColor = .blue
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: NSPoint?
    private var currentRect: NSRect?

    // Selection box appearance (computed from regionColor)
    private var selectionStrokeColor: NSColor {
        regionColor.nsColor.withAlphaComponent(0.9)
    }
    private var selectionFillColor: NSColor {
        regionColor.nsColor.withAlphaComponent(0.15)
    }
    private let guideColor = NSColor.white.withAlphaComponent(0.7)

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw instruction text
        let instruction = "ลากเมาส์เพื่อเลือกพื้นที่แปล — กด Esc เพื่อยกเลิก"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = instruction.size(withAttributes: attrs)
        let textPoint = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: bounds.height - textSize.height - 20
        )

        // Text background pill
        let pillRect = NSRect(
            x: textPoint.x - 12,
            y: textPoint.y - 6,
            width: textSize.width + 24,
            height: textSize.height + 12
        )
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.6).setFill()
        pill.fill()

        instruction.draw(at: textPoint, withAttributes: attrs)

        // Show current region color indicator
        let colorDotRect = NSRect(
            x: pillRect.minX - 18,
            y: textPoint.y + 2,
            width: 12,
            height: 12
        )
        let colorDot = NSBezierPath(ovalIn: colorDotRect)
        regionColor.nsColor.setFill()
        colorDot.fill()

        // Draw selection rectangle if dragging
        guard let rect = currentRect else { return }

        selectionFillColor.setFill()
        rect.fill()

        selectionStrokeColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 2
        border.setLineDash([6, 4], count: 2, phase: 0)
        border.stroke()

        // Draw size label
        let widthPx = Int(rect.width)
        let heightPx = Int(rect.height)
        let sizeText = "\(widthPx) × \(heightPx)"
        let sizeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let sizeTextSize = sizeText.size(withAttributes: sizeAttrs)
        let sizePoint = NSPoint(
            x: rect.maxX - sizeTextSize.width - 6,
            y: rect.minY + 4
        )

        let sizeBg = NSRect(
            x: sizePoint.x - 4,
            y: sizePoint.y - 2,
            width: sizeTextSize.width + 8,
            height: sizeTextSize.height + 4
        )
        NSColor.black.withAlphaComponent(0.5).setFill()
        sizeBg.fill()
        sizeText.draw(at: sizePoint, withAttributes: sizeAttrs)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        currentRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)
        setNeedsDisplay(bounds)
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 20, rect.height > 20 else {
            // Too small — ignore
            dragStart = nil
            currentRect = nil
            setNeedsDisplay(bounds)
            return
        }

        // Convert from NSView coordinates (bottom-left origin) to
        // normalized coordinates with top-left origin (matching OCR output).
        let normalized = CGRect(
            x: rect.origin.x / bounds.width,
            y: 1.0 - (rect.origin.y + rect.height) / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )

        onComplete?(normalized)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }
}
