import XCTest
import CoreGraphics
@testable import GameTranslator

/// T-0036: the Thai box stays still while the dialogue doesn't change
final class StableTextBoardTests: XCTestCase {
    // One still Switch dialogue screen (normalized boxes)
    private let speaker = text("Zelda", x: 0.10, y: 0.62, width: 0.08, height: 0.03)
    private let line1 = text("Link, the kingdom needs you.", x: 0.10, y: 0.70, width: 0.50, height: 0.04)
    private let line2 = text("Please find the three stones.", x: 0.10, y: 0.75, width: 0.52, height: 0.04)
    private let menu = [
        text("Map", x: 0.80, y: 0.05, width: 0.05, height: 0.03),
        text("Items", x: 0.80, y: 0.10, width: 0.06, height: 0.03),
        text("Quests", x: 0.80, y: 0.15, width: 0.07, height: 0.03),
        text("Options", x: 0.80, y: 0.20, width: 0.08, height: 0.03),
    ]
    /// Flickers in and out between OCR runs
    private let arrow = text("V", x: 0.60, y: 0.80, width: 0.02, height: 0.02)

    private var still: [DetectedText] { [speaker, line1, line2] + menu }

    private func moved(_ t: DetectedText, dx: CGFloat, dy: CGFloat) -> DetectedText {
        DetectedText(text: t.text, boundingBox: t.boundingBox.offsetBy(dx: dx, dy: dy), confidence: t.confidence)
    }

    private func renamed(_ t: DetectedText, _ string: String) -> DetectedText {
        DetectedText(text: string, boundingBox: t.boundingBox, confidence: t.confidence)
    }

    /// What the pipeline would show: text + screen rect for every translated text
    private func shown(_ texts: [DetectedText], translations: [String: String]) -> [String] {
        let options = RegionLayout.Options(autoFontSize: false, fixedFontSize: 16, showOriginalText: false)
        let regions = RegionLayout.buildRegions(
            from: texts, windowFrame: CGRect(x: 0, y: 0, width: 1470, height: 827), options: options,
            regionColor: nil, regionName: nil, translation: { translations[$0] }
        )
        return RegionLayout.resolveOverlaps(regions, options: options).map {
            "\($0.originalText) → \($0.translatedText) @ \(ScreenCaptureService.describe($0.screenRect))"
        }
    }

    // MARK: AC-1 — noisy readings of one still screen

    func testNoisyReadingsOfAStillScreenShowTheSameBoxes() {
        var board = StableTextBoard()
        let first = board.update(with: still)
        let translations = Dictionary(uniqueKeysWithValues: first.map { ($0.text, "TH:\($0.text)") })
        let expected = shown(first, translations: translations)

        let merged = DetectedText(text: "Link, the kingdom needs you. Please find the three stones.",
                                  boundingBox: line1.boundingBox.union(line2.boundingBox), confidence: 0.9)
        let splitA = DetectedText(text: "Please find the", boundingBox: CGRect(x: 0.10, y: 0.75, width: 0.28, height: 0.04), confidence: 0.9)
        let splitB = DetectedText(text: "three stones.", boundingBox: CGRect(x: 0.39, y: 0.751, width: 0.23, height: 0.04), confidence: 0.9)
        let jitter: CGFloat = 3.0 / 1470

        let runs: [[DetectedText]] = [
            still + [arrow],                                                    // 8 texts
            still,                                                              // 7 texts
            [speaker, renamed(line1, "Link, the kingdorn needs you."), line2] + menu, // misread letter
            [speaker, merged] + menu,                                              // lines merged
            [speaker, line1, splitA, splitB] + menu,                               // line split
            still.map { moved($0, dx: jitter, dy: -jitter) },                   // boxes ±3 px
            still + [arrow],
            [speaker, line1, line2] + menu.dropLast(),                             // one text missing once
            still,
        ]
        for (i, run) in runs.enumerated() {
            let output = board.update(with: run)
            XCTAssertTrue(output.allSatisfy { translations[$0.text] != nil || $0.text == arrow.text },
                          "run \(i): a new text would be sent for translation: \(output.map(\.text))")
            XCTAssertEqual(shown(output, translations: translations), expected, "run \(i)")
        }
    }

    // MARK: AC-2 — grace for a text missing once

    func testTextMissingOnceStaysAndMissingTwiceGoes() {
        var board = StableTextBoard()
        _ = board.update(with: still)
        let withoutLine2 = [speaker, line1] + menu

        let once = board.update(with: withoutLine2)
        XCTAssertTrue(once.contains { $0.text == line2.text })
        XCTAssertTrue(board.hasEntriesInGrace)

        let back = board.update(with: still)
        XCTAssertTrue(back.contains { $0.text == line2.text })
        XCTAssertFalse(board.hasEntriesInGrace)

        _ = board.update(with: withoutLine2)
        let twice = board.update(with: withoutLine2)
        XCTAssertFalse(twice.contains { $0.text == line2.text })
        XCTAssertFalse(board.hasEntriesInGrace)
    }

    // MARK: AC-3 — real changes

    func testNewLineIsShownAndOthersDoNotMove() {
        var board = StableTextBoard()
        let before = board.update(with: [speaker, line1])
        let newLine = text("Hurry, before nightfall!", x: 0.10, y: 0.80, width: 0.40, height: 0.04)
        let after = board.update(with: [speaker, line1, newLine])

        XCTAssertEqual(after.map(\.text), [speaker.text, line1.text, newLine.text])
        for old in before {
            XCTAssertEqual(after.first { $0.text == old.text }?.boundingBox, old.boundingBox)
        }
    }

    func testNextDialogueReplacesTheOldLineAtOnce() {
        var board = StableTextBoard()
        _ = board.update(with: [speaker, line1])
        let next = renamed(line1, "Go to the castle at dawn.")
        let output = board.update(with: [speaker, next])
        XCTAssertEqual(output.map(\.text), [speaker.text, next.text])
        XCTAssertFalse(board.hasEntriesInGrace, "the old line is replaced, not kept in grace")
    }

    /// Typewriter: each longer reading replaces the shorter one, the last one stays
    func testTypewriterTextFollowsUntilComplete() {
        var board = StableTextBoard()
        let steps = ["Wh", "Where is", "Where is the key", "Where is the key?"]
        var output: [DetectedText] = []
        for (i, step) in steps.enumerated() {
            let width = 0.05 + CGFloat(i) * 0.1
            output = board.update(with: [text(step, x: 0.10, y: 0.70, width: width, height: 0.04)])
        }
        XCTAssertEqual(output.map(\.text), ["Where is the key?"])
    }

    /// A short new line inside the old line's box is a change, not a piece of it
    func testShortNewLineIsNotTakenForAPieceOfTheOldOne() {
        var board = StableTextBoard()
        _ = board.update(with: [text("Yes. I know the way.", y: 0.70)])
        let output = board.update(with: [text("Yes.", y: 0.70, width: 0.1)])
        XCTAssertEqual(output.map(\.text), ["Yes."])
    }

    func testScrolledTextKeepsItsEntryAndMoves() {
        var board = StableTextBoard()
        _ = board.update(with: [line1])
        let scrolled = moved(line1, dx: 0, dy: -0.2)
        let output = board.update(with: [scrolled])
        XCTAssertEqual(output.map(\.text), [line1.text])
        XCTAssertEqual(output.first?.boundingBox, scrolled.boundingBox)
    }

    // MARK: Helpers

    func testNearlyEqualIgnoresSpacingAndAFewMisreads() {
        XCTAssertTrue(StableTextBoard.nearlyEqual("Please find the three stones.", "Please find the\nthree stones"))
        XCTAssertTrue(StableTextBoard.nearlyEqual("Please find the three stones.", "Please flnd the three stones."))
        XCTAssertFalse(StableTextBoard.nearlyEqual("Where is the key", "Where is the key to the"))
    }
}
