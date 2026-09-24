import XCTest
import CoreGraphics
@testable import GameTranslator

/// AC-2 (T-0020): image → screen mapping
final class CaptureGeometryTests: XCTestCase {
    private func assertRect(_ a: CGRect, _ b: CGRect, accuracy: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, file: file, line: line)
    }

    /// Full mapping as the app does it: buffer box → box in the captured window content →
    /// screen, using the mapping frame (captured size, aligned to the CG bounds' left/bottom)
    private func map(_ bufferBox: CGRect, buffer: CGSize, contentRect: CGRect?, contentScale: CGFloat?,
                     scaleFactor: CGFloat?, cgBounds: CGRect) -> CGRect {
        let content = CaptureGeometry.contentPixelRect(contentRect: contentRect, scaleFactor: scaleFactor, bufferSize: buffer)
        let captured = content == nil ? nil : CaptureGeometry.capturedWindowSize(contentRect: contentRect, contentScale: contentScale)
        let box = CaptureGeometry.boxInContent(bufferBox, bufferSize: buffer, content: content ?? CGRect(origin: .zero, size: buffer))
        return CaptureGeometry.screenRect(
            forContentBox: box,
            windowFrame: CaptureGeometry.mappingFrame(cgBounds: cgBounds, capturedSize: captured)
        )
    }

    // Buffer equal to the window

    func testBufferEqualToWindow() {
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        let buffer = CGSize(width: 1600, height: 1200)
        let screen = map(CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05), buffer: buffer,
                         contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), contentScale: 1, scaleFactor: 2, cgBounds: cg)
        assertRect(screen, CGRect(x: 300, y: 350, width: 80, height: 30))
    }

    func testNoFrameInfoUsesTheWholeBufferAndTheCGBounds() {
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        let screen = map(CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05), buffer: CGSize(width: 1600, height: 1200),
                         contentRect: nil, contentScale: nil, scaleFactor: nil, cgBounds: cg)
        assertRect(screen, CGRect(x: 300, y: 350, width: 80, height: 30))
    }

    // Content scaled inside the buffer — the owner's full-screen log (T-0020)

    func testOwnersFullScreenSceneMapsOntoTheText() throws {
        // Log: buffer=3840x2410 contentRect=(0,0 1743x1205) contentScale=0.908 scaleFactor=2.0,
        // CGWindowList bounds (0,38 1920x1205). Captured window ≈ 1920×1327 pt, top at y ≈ −84.
        let buffer = CGSize(width: 3840, height: 2410)
        let contentRect = CGRect(x: 0, y: 0, width: 1743, height: 1205)
        let contentScale: CGFloat = 0.908
        let cg = CGRect(x: 0, y: 38, width: 1920, height: 1205)

        let content = CaptureGeometry.contentPixelRect(contentRect: contentRect, scaleFactor: 2, bufferSize: buffer)
        assertRect(try XCTUnwrap(content), CGRect(x: 0, y: 0, width: 3486, height: 2410))
        let captured = try XCTUnwrap(CaptureGeometry.capturedWindowSize(contentRect: contentRect, contentScale: contentScale))
        XCTAssertEqual(captured.height, 1327, accuracy: 1)
        let mapping = CaptureGeometry.mappingFrame(cgBounds: cg, capturedSize: captured)
        XCTAssertEqual(mapping.minY, -84, accuracy: 1)
        XCTAssertEqual(mapping.maxY, cg.maxY, accuracy: 0.001, "same bottom edge")

        // "A polished brick of stone" on the owner's screen: x 499–926, y 555–595 pt
        // (screenshot px ÷ 1.042). Where that text is in the captured window:
        let text = CGRect(x: 499, y: 555, width: 427, height: 40)
        let inWindow = CGRect(x: (text.minX - mapping.minX) / mapping.width, y: (text.minY - mapping.minY) / mapping.height,
                              width: text.width / mapping.width, height: text.height / mapping.height)
        let bufferBox = CGRect(x: inWindow.minX * 3486 / 3840, y: inWindow.minY, width: inWindow.width * 3486 / 3840, height: inWindow.height)

        assertRect(map(bufferBox, buffer: buffer, contentRect: contentRect, contentScale: contentScale, scaleFactor: 2, cgBounds: cg),
                   text, accuracy: 2)

        // Round 1 mapped the same box onto the CG bounds → about one row too low
        let round1 = CaptureGeometry.screenRect(forContentBox: inWindow, windowFrame: cg)
        XCTAssertGreaterThan(round1.minY - text.minY, 40)
    }

    func testContentRectInPointsWithoutScaleFactorIsNotCropped() {
        // Interim review: a missing scaleFactor must not crop to the top-left quarter
        XCTAssertNil(CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 0, y: 0, width: 1470, height: 956), scaleFactor: nil, bufferSize: CGSize(width: 2940, height: 1912)
        ))
    }

    func testContentRectThatDoesNotFitIsNotUsed() {
        XCTAssertNil(CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 0, y: 0, width: 3000, height: 2000), scaleFactor: 2, bufferSize: CGSize(width: 2940, height: 1912)
        ))
    }

    func testContentFillingTheBufferIsNotCropped() {
        let buffer = CGSize(width: 1600, height: 1200)
        let content = try? XCTUnwrap(CaptureGeometry.contentPixelRect(
            contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), scaleFactor: 2, bufferSize: buffer
        ))
        XCTAssertFalse(CaptureGeometry.contentIsInset(content ?? .zero, bufferSize: buffer))
    }

    // Window size changed since start

    func testWindowSizeChangedSinceStartTargetsTheCapturedSize() {
        let configured = CaptureGeometry.captureSize(forWindow: CGSize(width: 1920, height: 1205))
        XCTAssertEqual(configured, .init(width: 3840, height: 2410))
        let target = CaptureGeometry.captureSize(forWindow: CGSize(width: 1920, height: 1327))
        XCTAssertTrue(CaptureGeometry.differs(target, configured))
        XCTAssertFalse(CaptureGeometry.differs(configured, .init(width: 3841, height: 2409)), "rounding noise")
    }

    func testRegionDrawnOverTheVisibleWindowMapsIntoTheCapturedImage() {
        // Region = bottom half of the visible window (CG bounds); the captured window is
        // 122 pt taller above it
        let visible = CGRect(x: 0, y: 38, width: 1920, height: 1205)
        let captured = CGRect(x: 0, y: -84, width: 1920, height: 1327)
        let region = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        let inImage = CaptureGeometry.convertNormalized(region, from: visible, to: captured)
        assertRect(CaptureGeometry.screenRect(forContentBox: inImage, windowFrame: captured),
                   CaptureGeometry.screenRect(forContentBox: region, windowFrame: visible))
        // Same frame both ways → unchanged
        assertRect(CaptureGeometry.convertNormalized(region, from: visible, to: visible), region)
    }

    func testTextAboveTheScreenIsNotVisible() {
        let visible = CGRect(x: 0, y: 38, width: 1920, height: 1205)
        XCTAssertFalse(CaptureGeometry.isVisible(CGRect(x: 100, y: -70, width: 200, height: 30), within: visible))
        XCTAssertTrue(CaptureGeometry.isVisible(CGRect(x: 100, y: 500, width: 200, height: 30), within: visible))
        XCTAssertTrue(CaptureGeometry.isVisible(CGRect(x: 100, y: 30, width: 200, height: 30), within: visible), "partly visible")
    }
}

/// T-0020: the stream size must not bounce between two sizes
final class ResizeGovernorTests: XCTestCase {
    private let configured = CaptureGeometry.PixelSize(width: 3840, height: 2410)
    private let target = CaptureGeometry.PixelSize(width: 3840, height: 2654)

    func testSameSizeNeverResizes() {
        var governor = ResizeGovernor()
        XCTAssertFalse(governor.shouldResize(to: configured, configured: configured, now: 0))
        XCTAssertFalse(governor.shouldResize(to: configured, configured: configured, now: 5))
    }

    func testNewSizeMustSettleFirst() {
        var governor = ResizeGovernor()
        XCTAssertFalse(governor.shouldResize(to: target, configured: configured, now: 0), "first sighting")
        XCTAssertFalse(governor.shouldResize(to: target, configured: configured, now: 0.2), "not settled yet")
        XCTAssertTrue(governor.shouldResize(to: target, configured: configured, now: 0.6))
    }

    func testChangingTargetRestartsTheWait() {
        // A full-screen transition passes through several sizes
        var governor = ResizeGovernor()
        _ = governor.shouldResize(to: target, configured: configured, now: 0)
        let other = CaptureGeometry.PixelSize(width: 3840, height: 2500)
        XCTAssertFalse(governor.shouldResize(to: other, configured: configured, now: 0.6))
        XCTAssertFalse(governor.shouldResize(to: other, configured: configured, now: 0.9))
        XCTAssertTrue(governor.shouldResize(to: other, configured: configured, now: 1.2))
    }

    func testBouncingBetweenTwoSizesIsCapped() {
        var governor = ResizeGovernor()
        var current = configured
        var resizes = 0
        var now: TimeInterval = 0
        // Worst case: after every resize the wanted size flips back
        for _ in 0..<40 {
            let wanted = current == configured ? target : configured
            if governor.shouldResize(to: wanted, configured: current, now: now) {
                resizes += 1
                current = wanted
            }
            now += 0.3
        }
        // 12 s simulated: at most 3 per 10 s window
        XCTAssertLessThanOrEqual(resizes, 6)
        XCTAssertTrue(governor.isHoldingBack(now: now) || resizes <= 3)
    }
}
