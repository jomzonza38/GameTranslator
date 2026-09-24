import CoreGraphics

/// Small picture of a text's original pixels, cut from the captured frame, so the
/// panel can show which on-screen text each translation belongs to (T-0018).
enum SourceThumbnail {
    /// Pixel rect in the captured image for an OCR bounding box (normalized 0…1,
    /// top-left origin — the convention OCRService produces), with a little padding,
    /// clamped inside the image. Nil if nothing is left.
    static func pixelRect(for box: CGRect, imageWidth: Int, imageHeight: Int, padding: CGFloat = 4) -> CGRect? {
        let width = CGFloat(imageWidth)
        let height = CGFloat(imageHeight)
        let rect = CGRect(
            x: box.minX * width - padding,
            y: box.minY * height - padding,
            width: box.width * width + 2 * padding,
            height: box.height * height + 2 * padding
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { return nil }
        return rect
    }

    /// Size that fits in `maxWidth` × `maxHeight` keeping the aspect ratio; never enlarged
    static func scaledSize(for size: CGSize, maxWidth: CGFloat = 560, maxHeight: CGFloat = 48) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// Cut `box` out of `image` into a small standalone image. The copy matters:
    /// `CGImage.cropping(to:)` alone would keep the whole captured frame in memory.
    static func make(from image: CGImage, box: CGRect) -> CGImage? {
        guard let rect = pixelRect(for: box, imageWidth: image.width, imageHeight: image.height),
              let cropped = image.cropping(to: rect) else { return nil }
        let size = scaledSize(for: rect.size)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
