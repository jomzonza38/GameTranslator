import XCTest
import CoreGraphics
@testable import GameTranslator

@MainActor
final class PanelHoverTests: XCTestCase {
    private func region(_ text: String, at rect: CGRect, regionColor: RegionColor? = nil, regionID: UUID? = nil) -> TranslatedRegion {
        TranslatedRegion(originalText: text, translatedText: "แปล \(text)", screenRect: rect, fontSize: 14,
                         regionColor: regionColor, regionID: regionID)
    }

    private let helloRect = CGRect(x: 100, y: 100, width: 200, height: 30)
    private let worldRect = CGRect(x: 100, y: 300, width: 200, height: 30)

    private func hoverHello(_ data: TranslationPanelData) throws {
        let hello = try XCTUnwrap(data.entries.first { $0.original == "Hello" })
        data.setHovered(hello.id, isInside: true)
    }

    // AC-1

    func testHoveredEntryMapsToItsSourceRect() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect), region("World", at: worldRect)])
        try hoverHello(data)
        XCTAssertEqual(data.highlight, .init(rect: helloRect, regionColor: nil))
    }

    func testHoverSurvivesAnUpdateWithUnchangedText() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect), region("World", at: worldRect)])
        try hoverHello(data)

        // Next frame: new region objects, same texts — Hello moved a little
        let moved = helloRect.offsetBy(dx: 0, dy: 12)
        data.update(from: [region("Hello", at: moved), region("World", at: worldRect)])
        XCTAssertEqual(data.highlight?.rect, moved, "outline follows the text")
    }

    func testOutlineUsesSourceRectNotThePushedDisplayRect() throws {
        let data = TranslationPanelData()
        // resolveOverlaps moved the box down to avoid an overlap
        let pushed = region("Hello", at: helloRect).withScreenRect(helloRect.offsetBy(dx: 0, dy: 40))
        data.update(from: [pushed])
        try hoverHello(data)
        XCTAssertEqual(data.highlight?.rect, helloRect)
    }

    func testRegionModeOutlineUsesTheRegionColour() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect, regionColor: .green, regionID: UUID())])
        try hoverHello(data)
        XCTAssertEqual(data.highlight?.regionColor, .green)
    }

    func testSameTextTwiceGetsDistinctEntries() {
        let data = TranslationPanelData()
        data.update(from: [region("OK", at: helloRect), region("OK", at: worldRect)])
        XCTAssertEqual(Set(data.entries.map(\.id)).count, 2)
    }

    // AC-2

    func testOutlineClearedWhenTheTextIsGone() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect), region("World", at: worldRect)])
        try hoverHello(data)

        data.update(from: [region("World", at: worldRect)])
        XCTAssertNil(data.highlight)
        XCTAssertNil(data.hoveredID)
    }

    func testOutlineClearedWhenThePipelineStops() throws {
        // stop / game closed → panel hide() → clear()
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect)])
        try hoverHello(data)
        data.clear()
        XCTAssertNil(data.highlight)
    }

    func testOutlineClearedWhenTheMouseLeaves() throws {
        let data = TranslationPanelData()
        data.update(from: [region("Hello", at: helloRect)])
        try hoverHello(data)
        let id = try XCTUnwrap(data.hoveredID)
        data.setHovered(id, isInside: false)
        XCTAssertNil(data.highlight)
    }
}
