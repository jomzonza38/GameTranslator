import AppKit
import CoreGraphics

/// Custom NSView that renders translated text labels over the game window
final class OverlayContentView: NSView {
    private var regions: [TranslatedRegion] = []
    /// Layers keyed by originalText — one layer per unique text prevents stacking
    private var textLayers: [String: CATextLayer] = [:]
    private var backgroundLayers: [String: CALayer] = [:]
    private let settings = AppSettings.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Update displayed text regions with smooth animation.
    /// Regions are keyed by `originalText` so duplicate texts at different positions
    /// collapse to a single overlay label — this prevents the stacking artifacts
    /// that appeared when scrolling text created multiple layers for the same string.
    func updateRegions(_ newRegions: [TranslatedRegion]) {
        // Deduplicate by originalText — keep the last occurrence (latest position)
        var deduped: [String: TranslatedRegion] = [:]
        for region in newRegions {
            deduped[region.originalText] = region
        }
        let uniqueRegions = Array(deduped.values)

        let currentKeys = Set(uniqueRegions.map(\.originalText))
        let previousKeys = Set(regions.map(\.originalText))

        // Remove layers for texts that are no longer present
        for key in previousKeys.subtracting(currentKeys) {
            fadeOutAndRemove(key: key)
        }

        // Add or update layers for current regions
        for region in uniqueRegions {
            if previousKeys.contains(region.originalText) {
                // Text existed before — smoothly move to new position
                updateLayer(for: region)
            } else {
                // Brand new text — create with fade in
                createLayer(for: region)
            }
        }

        self.regions = uniqueRegions
    }

    /// Clear all displayed regions
    func clearRegions() {
        for key in textLayers.keys {
            fadeOutAndRemove(key: key)
        }
        regions = []
    }

    // MARK: - Layer Management

    private func createLayer(for region: TranslatedRegion) {
        guard let parentLayer = layer else { return }

        // Background layer — fully opaque black for maximum readability
        let bgLayer = CALayer()
        bgLayer.backgroundColor = NSColor.black.cgColor
        bgLayer.cornerRadius = 4

        // Text layer
        let textLayer = CATextLayer()
        textLayer.string = createAttributedString(for: region)
        textLayer.isWrapped = true
        textLayer.truncationMode = .end
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.backgroundColor = NSColor.clear.cgColor

        // Position layers
        let rect = convertToViewCoordinates(region.screenRect)
        let padding: CGFloat = 4

        // Expand background slightly for padding
        let bgRect = rect.insetBy(dx: -padding, dy: -padding)
        bgLayer.frame = bgRect
        textLayer.frame = rect

        // Fade in
        bgLayer.opacity = 0
        textLayer.opacity = 0

        parentLayer.addSublayer(bgLayer)
        parentLayer.addSublayer(textLayer)

        backgroundLayers[region.originalText] = bgLayer
        textLayers[region.originalText] = textLayer

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        bgLayer.opacity = Float(settings.overlayBackgroundOpacity)
        textLayer.opacity = Float(settings.overlayOpacity)
        CATransaction.commit()
    }

    private func updateLayer(for region: TranslatedRegion) {
        guard let textLayer = textLayers[region.originalText],
              let bgLayer = backgroundLayers[region.originalText] else {
            // Layer missing — recreate
            createLayer(for: region)
            return
        }

        textLayer.string = createAttributedString(for: region)
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0

        let rect = convertToViewCoordinates(region.screenRect)
        let padding: CGFloat = 4

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        bgLayer.frame = rect.insetBy(dx: -padding, dy: -padding)
        textLayer.frame = rect
        CATransaction.commit()
    }

    private func fadeOutAndRemove(key: String) {
        guard let textLayer = textLayers.removeValue(forKey: key),
              let bgLayer = backgroundLayers.removeValue(forKey: key) else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setCompletionBlock {
            textLayer.removeFromSuperlayer()
            bgLayer.removeFromSuperlayer()
        }
        textLayer.opacity = 0
        bgLayer.opacity = 0
        CATransaction.commit()
    }

    // MARK: - Helpers

    private func createAttributedString(for region: TranslatedRegion) -> NSAttributedString {
        let fontSize = region.fontSize

        // Use a Thai-friendly font
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
        shadow.shadowOffset = NSSize(width: 1, height: -1)
        shadow.shadowBlurRadius = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .shadow: shadow
        ]

        let text = settings.showOriginalText
            ? "\(region.translatedText)\n(\(region.originalText))"
            : region.translatedText

        return NSAttributedString(string: text, attributes: attributes)
    }

    /// Convert from window-relative coordinates (origin top-left) to NSView coordinates (origin bottom-left)
    private func convertToViewCoordinates(_ rect: CGRect) -> CGRect {
        let viewHeight = bounds.height
        return CGRect(
            x: rect.origin.x,
            y: viewHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Pass through all mouse events
        return nil
    }
}
