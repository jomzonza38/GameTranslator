import CoreGraphics
import CoreVideo
import Foundation

// Capture card mode (T-0034): the Switch picture changes a little on every frame
// (capture noise, idle animation), so the exact fingerprint sent every frame to OCR
// and the fanless Mac throttled. These pure types decide when OCR is worth running.

/// Average brightness of a coarse grid over the picture (top-left origin, row-major).
/// One changed character changes its cell by much more than capture noise does.
struct LumaGrid: Equatable {
    static let defaultColumns = 48
    static let defaultRows = 27

    let columns: Int
    let rows: Int
    /// 0…255 per cell
    let values: [Float]

    /// Grid of BGRA pixels inside `content` (pixel rect; nil = everything). Samples
    /// every `step`-th pixel in both directions.
    static func of(bytes: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int,
                   content: CGRect? = nil, columns: Int = defaultColumns, rows: Int = defaultRows,
                   step: Int = 2) -> LumaGrid {
        let area = (content ?? CGRect(x: 0, y: 0, width: width, height: height))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        var sums = [Float](repeating: 0, count: columns * rows)
        var counts = [Int](repeating: 0, count: columns * rows)
        guard area.width >= 1, area.height >= 1 else {
            return LumaGrid(columns: columns, rows: rows, values: sums)
        }
        let x0 = Int(area.minX), y0 = Int(area.minY)
        let areaWidth = Int(area.width), areaHeight = Int(area.height)
        let pixels = bytes.assumingMemoryBound(to: UInt8.self)

        var y = 0
        while y < areaHeight {
            let row = y * rows / areaHeight
            let line = pixels + (y0 + y) * bytesPerRow
            var x = 0
            while x < areaWidth {
                let column = x * columns / areaWidth
                let p = line + (x0 + x) * 4 // B, G, R, A
                let luma = (29 * Int(p[0]) + 150 * Int(p[1]) + 77 * Int(p[2])) >> 8
                sums[row * columns + column] += Float(luma)
                counts[row * columns + column] += 1
                x += step
            }
            y += step
        }
        let values = zip(sums, counts).map { $1 > 0 ? $0 / Float($1) : 0 }
        return LumaGrid(columns: columns, rows: rows, values: values)
    }

    /// Grid of a 32-bit BGRA pixel buffer (nil for other formats)
    static func of(_ pixelBuffer: CVPixelBuffer, content: CGRect?) -> LumaGrid? {
        guard !CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        return of(bytes: UnsafeRawPointer(base), width: CVPixelBufferGetWidth(pixelBuffer),
                  height: CVPixelBufferGetHeight(pixelBuffer), bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                  content: content)
    }

    /// Indices of the cells touching `rect` (normalized, top-left origin; nil = all)
    func cells(in rect: CGRect?) -> [Int] {
        guard let rect else { return Array(values.indices) }
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return [] }
        let c0 = max(0, min(columns - 1, Int(clipped.minX * CGFloat(columns))))
        let c1 = max(0, min(columns - 1, Int((clipped.maxX * CGFloat(columns)).rounded(.up)) - 1))
        let r0 = max(0, min(rows - 1, Int(clipped.minY * CGFloat(rows))))
        let r1 = max(0, min(rows - 1, Int((clipped.maxY * CGFloat(rows)).rounded(.up)) - 1))
        guard c0 <= c1, r0 <= r1 else { return [] }
        return (r0...r1).flatMap { r in (c0...c1).map { r * columns + $0 } }
    }

    /// Whether any cell in `rect` differs from `other` by more than `threshold` levels.
    /// A grid of another shape always counts as different.
    func differs(from other: LumaGrid, in rect: CGRect? = nil, threshold: Float) -> Bool {
        guard columns == other.columns, rows == other.rows, values.count == other.values.count else { return true }
        return cells(in: rect).contains { abs(values[$0] - other.values[$0]) > threshold }
    }
}

/// Remembers the grid each area (the whole picture, or one capture region) was last
/// read with, and tells which areas changed since.
struct LumaChangeDetector {
    enum Area: Hashable {
        case whole
        case region(UUID)
    }

    /// Brightness levels a cell must move to count as a change. Capture noise
    /// averages out over a cell; one character moves its cell by far more.
    var threshold: Float = 3
    private(set) var baselines: [Area: LumaGrid] = [:]

    /// Areas (with their rect in the picture, normalized, nil = whole) that changed.
    /// An area never read before counts as changed.
    func changedAreas(_ grid: LumaGrid, areas: [(Area, CGRect?)]) -> Set<Area> {
        Set(areas.compactMap { area, rect in
            guard let baseline = baselines[area] else { return area }
            return grid.differs(from: baseline, in: rect, threshold: threshold) ? area : nil
        })
    }

    /// These areas were just read (OCR) with `grid`
    mutating func record(_ grid: LumaGrid, areas: [Area]) {
        for area in areas { baselines[area] = grid }
    }

    mutating func reset() {
        baselines.removeAll()
    }
}

/// Slows OCR down while it keeps reading the same text (an animated background in
/// the text area changes pixels but not the words): after `sameResultsBeforeSlowing`
/// runs with the same result, at most one run per `slowInterval` until the text changes.
struct OCRPacer {
    var sameResultsBeforeSlowing = 3
    var slowInterval: TimeInterval = 1

    private var lastSignature: String?
    private(set) var sameCount = 0
    private var lastRunAt: CFAbsoluteTime?

    var isSlowed: Bool { sameCount >= sameResultsBeforeSlowing }

    /// Seconds to wait before the next OCR run (0 = run now)
    func delayBeforeNextRun(now: CFAbsoluteTime) -> TimeInterval {
        guard isSlowed, let lastRunAt else { return 0 }
        return max(0, lastRunAt + slowInterval - now)
    }

    /// An OCR run finished; `signature` identifies the text it read
    mutating func recordRun(signature: String, at now: CFAbsoluteTime) {
        sameCount = signature == lastSignature ? sameCount + 1 : 0
        lastSignature = signature
        lastRunAt = now
    }

    mutating func reset() {
        lastSignature = nil
        sameCount = 0
        lastRunAt = nil
    }
}
