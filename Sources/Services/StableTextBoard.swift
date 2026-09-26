import CoreGraphics
import Foundation

/// Keeps what is shown still while the text on screen doesn't change (T-0036).
///
/// OCR of the same screen differs run to run: a misread letter, a line merged with
/// the next one or split from it, a text that appears in one run and not the next,
/// boxes a few pixels off. Shown as is, the Thai box fades out and in, jumps, and a
/// "new" text is sent for translation. The board remembers the texts on screen
/// (their first reading and box) and maps each new OCR run onto them:
/// - same text, or nearly (misread letters) → the remembered entry, remembered box;
/// - several pieces that together are a remembered text (split), or one reading
///   that is several remembered texts together (merge) → those entries;
/// - a text that grew (typewriter) or a different text at the same place → replaces
///   the entry there;
/// - an entry not read in a run stays for `graceRuns` more runs before it goes.
struct StableTextBoard {
    struct Entry: Equatable {
        var text: String
        /// Normalized box in the picture (as OCR gives it)
        var box: CGRect
        var confidence: Float
        /// Runs in a row this entry wasn't read
        var misses: Int
    }

    /// Runs an entry may be missing before it is removed
    var graceRuns = 1
    /// Texts at least this similar are the same text (misread letters)
    var similarityThreshold = 0.85
    /// A box is only moved when it overlaps its old place less than this (IoU)
    var moveThreshold: CGFloat = 0.6

    private(set) var entries: [Entry] = []

    /// Some entry wasn't read in the last run and is still shown — one more run
    /// decides whether it really left
    var hasEntriesInGrace: Bool { entries.contains { $0.misses > 0 } }

    /// Map one OCR run onto the board; returns the texts to show and translate
    /// (top to bottom)
    mutating func update(with texts: [DetectedText]) -> [DetectedText] {
        var seen = Set<Int>()
        var replaced = Set<Int>()
        var used = Set<Int>()
        var added: [Entry] = []

        // A. A remembered text read as several pieces this time (split): the pieces
        //    inside its box must add up to it, give or take a misread letter
        for index in entries.indices {
            let pieces = texts.indices.filter { !used.contains($0) && isInside(texts[$0].boundingBox, entries[index].box) }
            guard pieces.count >= 2 else { continue }
            let joined = pieces.sorted { Self.readsBefore(texts[$0].boundingBox, texts[$1].boundingBox) }
                .map { texts[$0].text }.joined(separator: " ")
            if Self.nearlyEqual(joined, entries[index].text) {
                seen.insert(index)
                used.formUnion(pieces)
            }
        }

        for textIndex in texts.indices where !used.contains(textIndex) {
            let text = texts[textIndex]

            // B1. Same text (anywhere — it may have scrolled)
            if let index = entries.indices.first(where: { !seen.contains($0) && entries[$0].text == text.text }) {
                seen.insert(index)
                if Self.iou(entries[index].box, text.boundingBox) < moveThreshold {
                    entries[index].box = text.boundingBox
                }
                continue
            }

            // B2. Several remembered texts read as one line (merge)
            let covered = entries.indices.filter { !seen.contains($0) && isInside(entries[$0].box, text.boundingBox) }
            if covered.count >= 2 {
                let joined = covered.sorted { Self.readsBefore(entries[$0].box, entries[$1].box) }
                    .map { entries[$0].text }.joined(separator: " ")
                if Self.nearlyEqual(joined, text.text) {
                    seen.formUnion(covered)
                    continue
                }
            }

            // B3. The same text here with a misread letter — but not text that is
            //     still typing out (it extends what was there)
            if let index = bestSimilar(to: text, excluding: seen) {
                seen.insert(index)
                if Self.iou(entries[index].box, text.boundingBox) < moveThreshold {
                    entries[index].box = text.boundingBox
                }
                continue
            }

            // B4. New or changed text — it replaces whatever was shown at the same place
            for index in entries.indices where !seen.contains(index)
                && Self.overlapOfSmaller(entries[index].box, text.boundingBox) > 0.5 {
                replaced.insert(index)
            }
            added.append(Entry(text: text.text, box: text.boundingBox, confidence: text.confidence, misses: 0))
        }

        var kept: [Entry] = []
        for index in entries.indices {
            var entry = entries[index]
            if seen.contains(index) {
                entry.misses = 0
            } else if replaced.contains(index) {
                continue
            } else {
                entry.misses += 1
            }
            if entry.misses <= graceRuns { kept.append(entry) }
        }
        entries = kept + added

        return entries
            .sorted { $0.box.minY < $1.box.minY }
            .map { DetectedText(text: $0.text, boundingBox: $0.box, confidence: $0.confidence) }
    }

    mutating func reset() {
        entries.removeAll()
    }

    // MARK: Matching

    private func bestSimilar(to text: DetectedText, excluding seen: Set<Int>) -> Int? {
        var best: (index: Int, similarity: Double)?
        for index in entries.indices where !seen.contains(index) && entries[index].box.intersects(text.boundingBox) {
            let old = entries[index].text
            // Typewriter: the new reading extends the old one — that's a change
            if text.text.count > old.count, text.text.hasPrefix(old) { continue }
            let similarity = TextTracker.similarity(old, text.text)
            if similarity >= similarityThreshold, similarity > (best?.similarity ?? 0) {
                best = (index, similarity)
            }
        }
        return best?.index
    }

    /// Reading order: upper line first; on the same line (tops within half a line
    /// height) left first
    static func readsBefore(_ a: CGRect, _ b: CGRect) -> Bool {
        let sameLine = abs(a.minY - b.minY) <= min(a.height, b.height) / 2
        return sameLine ? a.minX < b.minX : a.minY < b.minY
    }

    /// `inner` lies mostly inside `outer` (small jitter allowed)
    private func isInside(_ inner: CGRect, _ outer: CGRect) -> Bool {
        let area = inner.width * inner.height
        guard area > 0 else { return false }
        let overlap = inner.intersection(outer)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height / area >= 0.7
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return 0 }
        let intersection = overlap.width * overlap.height
        let union = a.width * a.height + b.width * b.height - intersection
        return union > 0 ? intersection / union : 0
    }

    /// Overlap as a share of the smaller box
    static func overlapOfSmaller(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? overlap.width * overlap.height / smaller : 0
    }

    /// Letters and digits only, lowercased — spacing, line breaks and punctuation
    /// differ between a merged and a split reading
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The same text apart from spacing/punctuation and at most a couple of misread
    /// characters (≤ 2, or 3 % of a long text). Stricter than `similarityThreshold`:
    /// text still typing out must not pass as a merge or split.
    static func nearlyEqual(_ a: String, _ b: String) -> Bool {
        let na = normalized(a), nb = normalized(b)
        guard !na.isEmpty, !nb.isEmpty else { return na == nb }
        if na == nb { return true }
        let allowed = max(2, Int(Double(max(na.count, nb.count)) * 0.03))
        guard abs(na.count - nb.count) <= allowed else { return false }
        return TextTracker.levenshteinDistance(na, nb) <= allowed
    }
}
