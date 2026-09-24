import CoreGraphics
import Foundation

/// Finds the panel entry whose source text is under the mouse in the game (T-0021)
enum GamePointer {
    /// `point` and the rects are CG screen coordinates. When rects overlap, the smallest
    /// one containing the point wins (the most specific text); the same text shown twice
    /// has two entries, and the one under the mouse is chosen.
    static func entryID(at point: CGPoint, in entries: [(id: String, sourceRect: CGRect)]) -> String? {
        entries
            .filter { $0.sourceRect.contains(point) }
            .min { $0.sourceRect.width * $0.sourceRect.height < $1.sourceRect.width * $1.sourceRect.height }?
            .id
    }
}

/// Reacts to where the mouse *rests*, not to where it passes: a text is selected only
/// after the mouse stayed over it — within `moveTolerance` points — for `restDelay`
/// seconds, and deselected the same way after it left. So the panel doesn't jump while
/// the player sweeps the mouse across the game (T-0021).
struct PointerRestTracker {
    var restDelay: TimeInterval = 0.4
    var moveTolerance: CGFloat = 6

    /// The entry currently marked (nil = none)
    private(set) var selected: String?

    private var candidate: String?
    private var anchor: CGPoint?
    private var candidateSince: TimeInterval = 0

    /// One sample: the entry under the mouse (or nil) and the mouse position
    mutating func update(hit: String?, at point: CGPoint, now: TimeInterval) -> String? {
        let moved = anchor.map { hypot(point.x - $0.x, point.y - $0.y) > moveTolerance } ?? true
        if hit != candidate || moved {
            candidate = hit
            anchor = point
            candidateSince = now
        }
        if now - candidateSince >= restDelay {
            selected = candidate
        }
        return selected
    }

    mutating func reset() {
        selected = nil
        candidate = nil
        anchor = nil
    }
}
