import AppKit

/// Converts between the two global screen coordinate systems macOS uses:
/// - **CG / Quartz** (ScreenCaptureKit, CGWindowList): origin at the top-left of the
///   *primary* display, y grows down.
/// - **AppKit** (NSWindow, NSScreen): origin at the bottom-left of the *primary*
///   display, y grows up.
/// Both are anchored to the primary display (the one with the menu bar,
/// `NSScreen.screens[0]`) — not `NSScreen.main`, which is whichever screen has the
/// key window. Using `NSScreen.main` shifts everything when displays differ in height.
enum ScreenCoordinates {
    /// CG rect → AppKit rect, given the primary display's height
    /// AppKit point (e.g. `NSEvent.mouseLocation`) → CG point, given the primary display's height
    static func cgPoint(fromAppKit point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    static func appKitRect(fromCG rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Index of the screen (AppKit frames) that shows most of `rect` (AppKit), or nil
    /// if it is on none of them
    static func indexOfScreen(showingMostOf rect: CGRect, screenFrames: [CGRect]) -> Int? {
        let areas = screenFrames.map { frame -> CGFloat in
            let overlap = frame.intersection(rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else {
            return nil
        }
        return best
    }

    /// CG rect → AppKit rect using the current primary display
    @MainActor
    static func appKitRect(fromCG rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        return appKitRect(fromCG: rect, primaryDisplayHeight: primary.frame.height)
    }

    /// The screen showing most of `rect` (AppKit), falling back to the primary display
    @MainActor
    static func screen(showingMostOf rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        if let index = indexOfScreen(showingMostOf: rect, screenFrames: screens.map(\.frame)) {
            return screens[index]
        }
        return screens.first
    }
}
