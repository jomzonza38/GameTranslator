import Foundation
import CoreGraphics

/// Tracks text changes between OCR frames to minimize redundant translations
final class TextTracker {
    /// Previous OCR frame for comparison
    private var previousFrame: OCRFrame?

    /// Threshold for considering text "changed" via fuzzy matching
    private let similarityThreshold: Double = 0.85

    /// Tolerance for position matching (normalized coordinates)
    private let positionTolerance: CGFloat = 0.08

    /// Analyze differences between current and previous OCR frames.
    ///
    /// Matching strategy (handles scrolling text):
    /// 1. First pass: match by position (within tolerance) — same as before.
    /// 2. Second pass: for unmatched texts, try matching by text content alone.
    ///    If the same string exists in both frames but at a different position,
    ///    treat it as "unchanged" (moved) rather than "new + removed".
    ///    This prevents ghost overlays when game text scrolls.
    func diff(currentFrame: OCRFrame) -> TextDiffResult {
        defer { previousFrame = currentFrame }

        guard let previous = previousFrame else {
            // First frame — everything is new
            return TextDiffResult(
                newTexts: currentFrame.texts,
                changedTexts: [],
                unchangedTexts: [],
                removedTexts: []
            )
        }

        var newTexts: [DetectedText] = []
        var changedTexts: [(old: DetectedText, new: DetectedText)] = []
        var unchangedTexts: [DetectedText] = []
        var matchedPreviousIndices: Set<Int> = []
        var unmatchedCurrentTexts: [DetectedText] = []

        // Pass 1: Match by position (within tolerance)
        for currentText in currentFrame.texts {
            var bestMatch: (index: Int, text: DetectedText, similarity: Double)?

            for (index, prevText) in previous.texts.enumerated() {
                guard !matchedPreviousIndices.contains(index) else { continue }

                // Check if positions are close enough
                guard currentText.boundingBox.approximately(equals: prevText.boundingBox, tolerance: positionTolerance) else {
                    continue
                }

                let similarity = stringSimilarity(currentText.text, prevText.text)

                if let best = bestMatch {
                    if similarity > best.similarity {
                        bestMatch = (index, prevText, similarity)
                    }
                } else {
                    bestMatch = (index, prevText, similarity)
                }
            }

            if let match = bestMatch {
                matchedPreviousIndices.insert(match.index)

                if match.similarity >= similarityThreshold {
                    // Text is essentially the same — no need to re-translate
                    unchangedTexts.append(currentText)
                } else {
                    // Text changed at this position — need to re-translate
                    changedTexts.append((old: match.text, new: currentText))
                }
            } else {
                // No position match — try text-based matching in pass 2
                unmatchedCurrentTexts.append(currentText)
            }
        }

        // Pass 2: Match remaining texts by content (handles scrolling)
        // Build a lookup of unmatched previous texts by their string
        var unmatchedPreviousByText: [String: Int] = [:]
        for (index, prevText) in previous.texts.enumerated() {
            if !matchedPreviousIndices.contains(index) {
                unmatchedPreviousByText[prevText.text] = index
            }
        }

        for currentText in unmatchedCurrentTexts {
            if let prevIndex = unmatchedPreviousByText[currentText.text] {
                // Same text at a different position — treat as "unchanged" (moved)
                matchedPreviousIndices.insert(prevIndex)
                unmatchedPreviousByText.removeValue(forKey: currentText.text)
                unchangedTexts.append(currentText)
            } else {
                // Also try fuzzy match on text content
                var bestFuzzy: (index: Int, similarity: Double)?
                for (text, index) in unmatchedPreviousByText {
                    let sim = stringSimilarity(currentText.text, text)
                    if sim >= similarityThreshold {
                        if let best = bestFuzzy {
                            if sim > best.similarity {
                                bestFuzzy = (index, sim)
                            }
                        } else {
                            bestFuzzy = (index, sim)
                        }
                    }
                }

                if let fuzzy = bestFuzzy {
                    let prevText = previous.texts[fuzzy.index]
                    matchedPreviousIndices.insert(fuzzy.index)
                    unmatchedPreviousByText.removeValue(forKey: prevText.text)
                    // Similar enough text at different position — treat as moved+changed
                    changedTexts.append((old: prevText, new: currentText))
                } else {
                    // Truly new text
                    newTexts.append(currentText)
                }
            }
        }

        // Previous texts that weren't matched — they've been removed
        let removedTexts = previous.texts.enumerated()
            .filter { !matchedPreviousIndices.contains($0.offset) }
            .map { $0.element }

        return TextDiffResult(
            newTexts: newTexts,
            changedTexts: changedTexts,
            unchangedTexts: unchangedTexts,
            removedTexts: removedTexts
        )
    }

    /// Reset tracking state
    func reset() {
        previousFrame = nil
    }

    // MARK: - String Similarity (Levenshtein-based)

    /// Calculate similarity between two strings (0.0 = completely different, 1.0 = identical)
    private func stringSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1.0 }
        if a.isEmpty || b.isEmpty { return 0.0 }

        let distance = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Compute Levenshtein edit distance between two strings
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        // Optimization: if length difference is too large, skip detailed computation
        if abs(m - n) > max(m, n) / 2 {
            return max(m, n)
        }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,      // deletion
                    curr[j - 1] + 1,   // insertion
                    prev[j - 1] + cost // substitution
                )
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }
}

/// Result of comparing two OCR frames
struct TextDiffResult {
    /// Texts that appeared for the first time
    let newTexts: [DetectedText]
    /// Texts that changed at the same position
    let changedTexts: [(old: DetectedText, new: DetectedText)]
    /// Texts that haven't changed (use cached translation)
    let unchangedTexts: [DetectedText]
    /// Texts that disappeared from the screen
    let removedTexts: [DetectedText]

    /// Whether there are any changes requiring translation
    var hasChanges: Bool {
        !newTexts.isEmpty || !changedTexts.isEmpty || !removedTexts.isEmpty
    }

    /// All texts that need to be translated
    var textsNeedingTranslation: [DetectedText] {
        newTexts + changedTexts.map(\.new)
    }
}
