import AppKit
import CoreGraphics

/// Pure layout helpers for the pipeline: merging OCR lines, sizing and
/// positioning translated boxes. No state — easy to unit test.
enum RegionLayout {
    struct Options {
        var autoFontSize: Bool
        var fixedFontSize: CGFloat
        var showOriginalText: Bool
    }

    // MARK: - Line Merging

    /// Merge vertically adjacent, horizontally overlapping OCR lines into one text
    /// (dialog boxes usually wrap one sentence over several lines).
    /// - Parameter separator: " " for languages with word spacing, "" for CJK
    static func mergeAdjacentLines(_ frame: OCRFrame, separator: String = " ") -> OCRFrame {
        guard frame.texts.count > 1 else { return frame }

        let lines = frame.texts.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        var merged: [DetectedText] = []
        var i = 0

        while i < lines.count {
            var current = lines[i]
            i += 1

            while i < lines.count {
                let next = lines[i]
                let currentBox = current.boundingBox
                let nextBox = next.boundingBox

                let gap = nextBox.minY - currentBox.maxY
                let lineHeight = currentBox.height

                let gapOK = gap >= -0.01 && gap < lineHeight * 1.5

                let overlapLeft = max(currentBox.minX, nextBox.minX)
                let overlapRight = min(currentBox.maxX, nextBox.maxX)
                let overlapWidth = max(0, overlapRight - overlapLeft)
                let minWidth = min(currentBox.width, nextBox.width)
                let horizontalOK = minWidth > 0 && (overlapWidth / minWidth) > 0.3

                guard gapOK && horizontalOK else { break }

                let mergedText = current.text + separator + next.text
                let mergedBox = CGRect(
                    x: min(currentBox.minX, nextBox.minX),
                    y: min(currentBox.minY, nextBox.minY),
                    width: max(currentBox.maxX, nextBox.maxX) - min(currentBox.minX, nextBox.minX),
                    height: nextBox.maxY - currentBox.minY
                )
                let mergedConfidence = min(current.confidence, next.confidence)

                current = DetectedText(
                    text: mergedText,
                    boundingBox: mergedBox,
                    confidence: mergedConfidence
                )
                i += 1
            }

            merged.append(current)
        }

        return OCRFrame(texts: merged, imageSize: frame.imageSize)
    }

    // MARK: - Region Building

    /// Convert detected texts + their translations into on-screen regions.
    /// Texts without a translation are skipped.
    static func buildRegions(
        from texts: [DetectedText],
        windowFrame: CGRect,
        options: Options,
        regionColor: RegionColor?,
        regionName: String?,
        translation: (String) -> String?
    ) -> [TranslatedRegion] {
        texts.compactMap { detected -> TranslatedRegion? in
            guard let translated = translation(detected.text) else { return nil }

            // Convert normalized bounding box to screen coordinates
            let screenRect = CGRect(
                x: windowFrame.origin.x + detected.boundingBox.origin.x * windowFrame.width,
                y: windowFrame.origin.y + detected.boundingBox.origin.y * windowFrame.height,
                width: detected.boundingBox.width * windowFrame.width,
                height: detected.boundingBox.height * windowFrame.height
            )

            var fontSize = options.autoFontSize
                ? OCRService.estimateFontSize(
                    boundingBoxHeight: detected.boundingBox.height,
                    windowHeight: windowFrame.height
                )
                : options.fixedFontSize

            // Auto-shrink font so the Thai translation fits within ~1.5x the original
            let text = displayText(translation: translated, original: detected.text, options: options)
            let maxHeight = screenRect.height * 1.5
            let minFontSize: CGFloat = 8

            while fontSize > minFontSize {
                let estimatedHeight = estimateTextHeight(text, width: screenRect.width, fontSize: fontSize)
                if estimatedHeight <= maxHeight {
                    break
                }
                fontSize -= 1
            }

            return TranslatedRegion(
                originalText: detected.text,
                translatedText: translated,
                screenRect: screenRect,
                fontSize: fontSize,
                regionColor: regionColor,
                regionName: regionName
            )
        }
    }

    // MARK: - Overlap Resolution

    /// Grow boxes to fit their text, then push boxes that collide further down
    static func resolveOverlaps(_ regions: [TranslatedRegion], options: Options) -> [TranslatedRegion] {
        guard regions.count > 1 else {
            return regions.map { adjustHeight(for: $0, options: options) }
        }

        var placed = regions.map { adjustHeight(for: $0, options: options) }
        placed.sort { $0.screenRect.minY < $1.screenRect.minY }

        let gap: CGFloat = 4
        for i in 1..<placed.count {
            for j in 0..<i {
                let a = placed[j].screenRect
                let b = placed[i].screenRect

                let xOverlap = a.minX < b.maxX && b.minX < a.maxX
                let yOverlap = a.minY < b.maxY && b.minY < a.maxY

                if xOverlap && yOverlap {
                    let newRect = CGRect(x: b.origin.x, y: a.maxY + gap, width: b.width, height: b.height)
                    placed[i] = placed[i].withScreenRect(newRect)
                }
            }
        }

        return placed
    }

    static func adjustHeight(for region: TranslatedRegion, options: Options) -> TranslatedRegion {
        let text = displayText(translation: region.translatedText, original: region.originalText, options: options)
        let estimatedHeight = estimateTextHeight(text, width: region.screenRect.width, fontSize: region.fontSize)

        guard estimatedHeight > region.screenRect.height else { return region }

        let cappedHeight = min(estimatedHeight, region.screenRect.height * 1.5)
        let newRect = CGRect(
            x: region.screenRect.origin.x,
            y: region.screenRect.origin.y,
            width: region.screenRect.width,
            height: cappedHeight
        )
        return region.withScreenRect(newRect)
    }

    // MARK: - Text Measurement

    static func displayText(translation: String, original: String, options: Options) -> String {
        options.showOriginalText ? "\(translation)\n(\(original))" : translation
    }

    static func estimateTextHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 40), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ],
            context: nil
        )
        return ceil(rect.height) + 8
    }
}
