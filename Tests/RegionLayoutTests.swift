import XCTest
@testable import GameTranslator

final class RegionLayoutTests: XCTestCase {
    func testMergesWrappedDialogLines() {
        let input = frame([
            text("and then we", y: 0.14, height: 0.04),
            text("Once upon a time", y: 0.10, height: 0.04)
        ])
        let merged = RegionLayout.mergeAdjacentLines(input)

        XCTAssertEqual(merged.texts.map(\.text), ["Once upon a time and then we"])
        XCTAssertEqual(merged.texts.first?.boundingBox.minY ?? 0, 0.10, accuracy: 0.0001)
        XCTAssertEqual(merged.texts.first?.boundingBox.maxY ?? 0, 0.18, accuracy: 0.0001)
    }

    func testCJKLinesMergeWithoutSpace() {
        let input = frame([text("こんにちは", y: 0.10), text("世界", y: 0.14)])
        let merged = RegionLayout.mergeAdjacentLines(input, separator: "")
        XCTAssertEqual(merged.texts.map(\.text), ["こんにちは世界"])
    }

    func testDoesNotMergeDistantOrSideBySideText() {
        let farApart = frame([text("HP 100", y: 0.05), text("MP 50", y: 0.60)])
        XCTAssertEqual(RegionLayout.mergeAdjacentLines(farApart).texts.count, 2)

        let sideBySide = frame([
            text("Left menu", x: 0.0, y: 0.10, width: 0.2),
            text("Right menu", x: 0.7, y: 0.14, width: 0.2)
        ])
        XCTAssertEqual(RegionLayout.mergeAdjacentLines(sideBySide).texts.count, 2)
    }

    func testBuildRegionsSkipsUntranslatedAndMapsToScreen() {
        let options = RegionLayout.Options(autoFontSize: false, fixedFontSize: 14, showOriginalText: false)
        let regions = RegionLayout.buildRegions(
            from: [text("Hello", x: 0.5, y: 0.5, width: 0.25, height: 0.1), text("Untranslated", y: 0.1)],
            windowFrame: CGRect(x: 100, y: 200, width: 1000, height: 500),
            options: options,
            regionColor: nil,
            regionName: nil,
            translation: { $0 == "Hello" ? "สวัสดี" : nil }
        )

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].translatedText, "สวัสดี")
        XCTAssertEqual(regions[0].screenRect, CGRect(x: 600, y: 450, width: 250, height: 50))
    }

    func testResolveOverlapsPushesCollidingBoxDown() {
        let options = RegionLayout.Options(autoFontSize: false, fixedFontSize: 12, showOriginalText: false)
        let top = TranslatedRegion(originalText: "a", translatedText: "ก", screenRect: CGRect(x: 0, y: 0, width: 300, height: 40), fontSize: 12)
        let overlapping = TranslatedRegion(originalText: "b", translatedText: "ข", screenRect: CGRect(x: 10, y: 20, width: 300, height: 40), fontSize: 12)

        let resolved = RegionLayout.resolveOverlaps([overlapping, top], options: options)

        XCTAssertEqual(resolved.count, 2)
        XCTAssertLessThanOrEqual(resolved[0].screenRect.maxY + 4, resolved[1].screenRect.minY + 0.001)
    }

    func testCleanOCRText() {
        XCTAssertEqual(OCRService.cleanOCRText("Helllllo   world"), "Hello world")
        XCTAssertEqual(OCRService.cleanOCRText("|Start Game~"), "Start Game")
        XCTAssertEqual(OCRService.cleanOCRText("Wait... what?!!!"), "Wait... what?!!!")
    }
}
