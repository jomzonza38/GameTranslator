import Foundation
import CoreGraphics

/// Represents a translated text region to be displayed on the overlay
struct TranslatedRegion: Identifiable {
    let id: UUID
    /// Original English text
    let originalText: String
    /// Translated Thai text
    let translatedText: String
    /// Bounding box in screen coordinates (pixels)
    let screenRect: CGRect
    /// Where the original text is on screen (CG screen coordinates). Unlike
    /// `screenRect`, not moved when overlapping boxes are pushed apart (T-0019).
    let sourceRect: CGRect
    /// Font size estimated from the original text size
    let fontSize: CGFloat
    /// Whether this translation is still being processed
    let isPending: Bool
    /// When this region was last updated
    let lastUpdated: Date
    /// Color of the capture region this text belongs to (nil = full-screen/no region)
    let regionColor: RegionColor?
    /// Name of the capture region this text belongs to
    let regionName: String?
    /// ID of the capture region this text belongs to (nil = full-screen)
    let regionID: UUID?
    /// Picture of the original text as it looks in the game (panel, full-screen mode)
    let sourceThumbnail: CGImage?

    init(
        originalText: String,
        translatedText: String,
        screenRect: CGRect,
        fontSize: CGFloat,
        isPending: Bool = false,
        regionColor: RegionColor? = nil,
        regionName: String? = nil,
        regionID: UUID? = nil,
        sourceThumbnail: CGImage? = nil,
        sourceRect: CGRect? = nil
    ) {
        self.id = UUID()
        self.originalText = originalText
        self.translatedText = translatedText
        self.screenRect = screenRect
        self.sourceRect = sourceRect ?? screenRect
        self.fontSize = fontSize
        self.isPending = isPending
        self.lastUpdated = Date()
        self.regionColor = regionColor
        self.regionName = regionName
        self.regionID = regionID
        self.sourceThumbnail = sourceThumbnail
    }

    /// Create a copy with updated translation
    func withTranslation(_ translation: String) -> TranslatedRegion {
        TranslatedRegion(
            originalText: originalText,
            translatedText: translation,
            screenRect: screenRect,
            fontSize: fontSize,
            isPending: false,
            regionColor: regionColor,
            regionName: regionName,
            regionID: regionID,
            sourceThumbnail: sourceThumbnail,
            sourceRect: sourceRect
        )
    }

    /// Create a copy with updated screen position
    func withScreenRect(_ rect: CGRect) -> TranslatedRegion {
        TranslatedRegion(
            originalText: originalText,
            translatedText: translatedText,
            screenRect: rect,
            fontSize: fontSize,
            isPending: isPending,
            regionColor: regionColor,
            regionName: regionName,
            regionID: regionID,
            sourceThumbnail: sourceThumbnail,
            sourceRect: sourceRect
        )
    }

    /// Create a copy with a picture of the original text
    func withSourceThumbnail(_ thumbnail: CGImage?) -> TranslatedRegion {
        TranslatedRegion(
            originalText: originalText,
            translatedText: translatedText,
            screenRect: screenRect,
            fontSize: fontSize,
            isPending: isPending,
            regionColor: regionColor,
            regionName: regionName,
            regionID: regionID,
            sourceThumbnail: thumbnail,
            sourceRect: sourceRect
        )
    }
}
