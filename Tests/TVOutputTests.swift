import XCTest
import CoreGraphics
import CoreMedia
@testable import GameTranslator

/// AC-1 (T-0027): capture format choice, output display choice, aspect-fit rect,
/// capture card / audio device matching. AC-1 (T-0030): frame durations are always
/// ones the format supports, including discrete 59.94 / 29.97 ranges.
final class TVOutputTests: XCTestCase {
    private let usb = CaptureCardSelection.fourCC("usb ")
    private let builtIn = CaptureCardSelection.builtInTransport
    private let virtual = CaptureCardSelection.virtualTransport

    /// A continuous range from integer rates (durations 1/max … 1/min)
    private func range(_ minFPS: Int32, _ maxFPS: Int32) -> CaptureFrameRateRange {
        CaptureFrameRateRange(minFrameRate: Double(minFPS), maxFrameRate: Double(maxFPS),
                              minFrameDuration: CMTime(value: 1, timescale: maxFPS),
                              maxFrameDuration: CMTime(value: 1, timescale: minFPS))
    }

    /// A discrete range as UVC cards report it: min = max, exact NTSC-style duration
    private func discrete(_ duration: CMTime) -> CaptureFrameRateRange {
        let fps = Double(duration.timescale) / Double(duration.value)
        return CaptureFrameRateRange(minFrameRate: fps, maxFrameRate: fps,
                                     minFrameDuration: duration, maxFrameDuration: duration)
    }

    private let d60 = CMTime(value: 1, timescale: 60)
    private let d5994 = CMTime(value: 1001, timescale: 60000)
    private let d30 = CMTime(value: 1, timescale: 30)
    private let d2997 = CMTime(value: 1001, timescale: 30000)

    private func format(_ w: Int, _ h: Int, _ fps: Int32, _ fourCC: String, minFPS: Int32 = 5) -> CaptureFormatCandidate {
        CaptureFormatCandidate(width: w, height: h, frameRateRanges: [range(minFPS, fps)], fourCC: fourCC)
    }

    private func format(_ ranges: [CaptureFrameRateRange]) -> CaptureFormatCandidate {
        CaptureFormatCandidate(width: 1920, height: 1080, frameRateRanges: ranges, fourCC: "jpeg")
    }

    private func assertSupported(_ duration: CMTime?, _ expected: CMTime, in f: CaptureFormatCandidate,
                                 file: StaticString = #filePath, line: UInt = #line) {
        guard let duration else { return XCTFail("no duration", file: file, line: line) }
        XCTAssertEqual(CMTimeCompare(duration, expected), 0, "\(duration) ≠ \(expected)", file: file, line: line)
        XCTAssertTrue(CaptureCardSelection.isSupported(duration, by: f.frameRateRanges), file: file, line: line)
    }

    private func device(_ name: String, _ transport: Int32) -> CaptureDeviceCandidate {
        CaptureDeviceCandidate(name: name, uniqueID: name, transportType: transport)
    }

    // MARK: Format choice

    /// A typical USB 2 card: uncompressed only at low frame rates, MJPEG up to 4K30
    func testPicks1080p60MJPEGOverSlowUncompressedAnd4K30() {
        let formats = [
            format(1920, 1080, 5, "yuvs"),
            format(1280, 720, 10, "yuvs"),
            format(3840, 2160, 30, "jpeg"),
            format(1280, 720, 60, "jpeg"),
            format(1920, 1080, 60, "jpeg"),
        ]
        XCTAssertEqual(CaptureCardSelection.bestFormatIndex(in: formats), 4)
    }

    func testPrefersUncompressedAtTheSameSizeAndRate() {
        let formats = [format(1920, 1080, 60, "jpeg"), format(1920, 1080, 60, "2vuy")]
        XCTAssertEqual(CaptureCardSelection.bestFormatIndex(in: formats), 1)
    }

    func testLargerPictureBeatsUncompressedSmallerOne() {
        let formats = [format(1280, 720, 60, "2vuy"), format(1920, 1080, 60, "jpeg")]
        XCTAssertEqual(CaptureCardSelection.bestFormatIndex(in: formats), 1)
    }

    func testOnlyAbove1080pPicksTheSmallest() {
        let formats = [format(3840, 2160, 60, "jpeg"), format(2560, 1440, 60, "jpeg")]
        XCTAssertEqual(CaptureCardSelection.bestFormatIndex(in: formats), 1)
    }

    func testFiftyFPSCountsAsFast() {
        let formats = [format(1920, 1080, 30, "jpeg"), format(1280, 720, 50, "jpeg")]
        XCTAssertEqual(CaptureCardSelection.bestFormatIndex(in: formats), 1)
    }

    func testNoFormats() {
        XCTAssertNil(CaptureCardSelection.bestFormatIndex(in: []))
    }

    // MARK: Frame duration (T-0030)

    func testDiscreteSixty() {
        let f = format([discrete(d30), discrete(d60)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), d60, in: f)
    }

    /// The crash case: 1/60 is not in a discrete 59.94 range → its own 1001/60000
    func testDiscrete5994UsesTheRangesOwnDuration() {
        let f = format([discrete(d2997), discrete(d5994)])
        let duration = CaptureCardSelection.frameDuration(for: f)
        assertSupported(duration, d5994, in: f)
        XCTAssertFalse(CaptureCardSelection.isSupported(d60, by: f.frameRateRanges))
    }

    func testDiscreteThirty() {
        let f = format([discrete(d30)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), d30, in: f)
    }

    func testDiscrete2997() {
        let f = format([discrete(d2997)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), d2997, in: f)
    }

    func testContinuousRangeContainingSixty() {
        let f = format([range(5, 120)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), d60, in: f)
    }

    func testContinuousRangeOnlyBelowSixty() {
        let f = format([range(5, 30)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), d30, in: f)
    }

    func testContinuousRangeOnlyAboveSixtyUsesTheSlowestRate() {
        let f = format([range(120, 240)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), CMTime(value: 1, timescale: 120), in: f)
    }

    func testFixedHighRateOnly() {
        let f = format([range(120, 120)])
        assertSupported(CaptureCardSelection.frameDuration(for: f), CMTime(value: 1, timescale: 120), in: f)
    }

    func testNoRangesGivesNil() {
        XCTAssertNil(CaptureCardSelection.frameDuration(for: format([])))
    }

    func testInvalidDurationIsNeverSupported() {
        XCTAssertFalse(CaptureCardSelection.isSupported(.invalid, by: [range(5, 60)]))
        XCTAssertFalse(CaptureCardSelection.isSupported(CMTime(value: 0, timescale: 60), by: [range(5, 60)]))
    }

    func testDescription() {
        XCTAssertEqual(CaptureCardSelection.describe(width: 1920, height: 1080, fourCC: "jpeg", frameRate: 60),
                       "1920×1080 @ 60 fps · MJPEG")
        XCTAssertEqual(CaptureCardSelection.describe(width: 1920, height: 1080, fourCC: "jpeg",
                                                     frameRate: CaptureCardSelection.frameRate(of: d5994)),
                       "1920×1080 @ 59.94 fps · MJPEG")
        XCTAssertEqual(CaptureCardSelection.describe(width: 1280, height: 720, fourCC: "2vuy", frameRate: nil),
                       "1280×720 @ ? fps · UYVY (ไม่บีบอัด)")
    }

    func testFourCCRoundTrip() {
        XCTAssertEqual(CaptureCardSelection.fourCCString(UInt32(bitPattern: CaptureCardSelection.fourCC("jpeg"))), "jpeg")
    }

    // MARK: Capture card

    func testSkipsVirtualCameras() {
        let devices = [device("OBS Virtual Camera", usb), device("Other", virtual), device("USB3.0 Capture", usb)]
        XCTAssertEqual(CaptureCardSelection.firstCaptureCard(in: devices)?.name, "USB3.0 Capture")
    }

    func testNoCaptureCard() {
        XCTAssertNil(CaptureCardSelection.firstCaptureCard(in: [device("OBS Virtual Camera", usb)]))
        XCTAssertNil(CaptureCardSelection.firstCaptureCard(in: []))
    }

    // MARK: Audio device

    func testAudioWithTheSameNameAsTheCard() {
        let audio = [device("MacBook Air Microphone", builtIn), device("USB3.0 Capture", usb)]
        XCTAssertEqual(CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: "USB3.0 Capture", in: audio)?.name,
                       "USB3.0 Capture")
    }

    func testAudioSharingTheBrandWord() {
        let audio = [device("MacBook Air Microphone", builtIn), device("Kingma Audio", usb)]
        XCTAssertEqual(CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: "Kingma HDMI Video", in: audio)?.name,
                       "Kingma Audio")
    }

    func testNeverTheMacMicrophone() {
        // Even a built-in device with the card's name is refused
        let audio = [device("MacBook Air Microphone", builtIn), device("USB3.0 Capture", builtIn)]
        XCTAssertNil(CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: "USB3.0 Capture", in: audio))
    }

    func testNotAnUnrelatedUSBMicOrVirtualDevice() {
        let audio = [device("Blue Yeti USB Microphone", usb), device("BlackHole 2ch", virtual),
                     device("USB Audio Device", usb)]
        XCTAssertNil(CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: "USB3.0 Capture", in: audio))
        XCTAssertNil(CaptureCardSelection.matchingAudioDevice(forVideoDeviceNamed: "Kingma HDMI Video", in: audio))
    }

    // MARK: Output display

    private func display(_ id: CGDirectDisplayID, builtIn: Bool, primary: Bool) -> TVDisplayCandidate {
        TVDisplayCandidate(displayID: id, isBuiltIn: builtIn, isPrimary: primary)
    }

    func testPicksTheExternalDisplay() {
        let displays = [display(1, builtIn: true, primary: true), display(2, builtIn: false, primary: false)]
        XCTAssertEqual(TVOutputLayout.outputDisplayIndex(in: displays), 1)
    }

    func testTVSetAsPrimaryIsStillChosen() {
        let displays = [display(2, builtIn: false, primary: true), display(1, builtIn: true, primary: false)]
        XCTAssertEqual(TVOutputLayout.outputDisplayIndex(in: displays), 0)
    }

    func testTwoExternalPrefersTheNonPrimary() {
        let displays = [display(3, builtIn: false, primary: true), display(4, builtIn: false, primary: false)]
        XCTAssertEqual(TVOutputLayout.outputDisplayIndex(in: displays), 1)
    }

    func testOnlyBuiltInDisplayGivesNil() {
        XCTAssertNil(TVOutputLayout.outputDisplayIndex(in: [display(1, builtIn: true, primary: true)]))
        XCTAssertNil(TVOutputLayout.outputDisplayIndex(in: []))
    }

    // MARK: Window on the Mac (T-0032)

    func testMacWindowUsesTheBuiltInDisplayEvenWithATV() {
        let displays = [display(2, builtIn: false, primary: true), display(1, builtIn: true, primary: false)]
        XCTAssertEqual(TVOutputLayout.macDisplayIndex(in: displays), 1)
    }

    func testMacWindowWithoutBuiltInDisplayUsesThePrimary() {
        let displays = [display(3, builtIn: false, primary: false), display(4, builtIn: false, primary: true)]
        XCTAssertEqual(TVOutputLayout.macDisplayIndex(in: displays), 1)
        XCTAssertNil(TVOutputLayout.macDisplayIndex(in: []))
    }

    func testDefaultWindowSizeKeepsThePicturesAspectRatio() {
        // MacBook Air visible frame (16:10 screen), 16:9 picture
        let size = CaptureCardWindowLayout.defaultContentSize(video: CGSize(width: 1920, height: 1080),
                                                              visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 919))
        XCTAssertEqual(size.width / size.height, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(size.width, 1470 * 0.75, accuracy: 0.5)
        XCTAssertLessThanOrEqual(size.height, 919 * 0.75)
    }

    func testDefaultWindowSizeOnATallScreenIsLimitedByHeight() {
        let size = CaptureCardWindowLayout.defaultContentSize(video: CGSize(width: 1920, height: 1080),
                                                              visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 400))
        XCTAssertEqual(size.height, 300, accuracy: 0.5)
        XCTAssertEqual(size.width / size.height, 16.0 / 9.0, accuracy: 0.001)
    }

    func testSavedSizeIsCorrectedToThePicturesAspectRatio() {
        // Saved from a 4:3 format, now the card sends 16:9: width kept, height follows
        XCTAssertEqual(CaptureCardWindowLayout.keepingAspect(CGSize(width: 800, height: 600), video: CGSize(width: 1920, height: 1080)),
                       CGSize(width: 800, height: 450))
        // Already right: unchanged
        XCTAssertEqual(CaptureCardWindowLayout.keepingAspect(CGSize(width: 1280, height: 720), video: CGSize(width: 1920, height: 1080)),
                       CGSize(width: 1280, height: 720))
        // Unknown picture size: unchanged
        XCTAssertEqual(CaptureCardWindowLayout.keepingAspect(CGSize(width: 800, height: 600), video: .zero),
                       CGSize(width: 800, height: 600))
    }

    // MARK: Aspect fit

    func testSameAspectFillsTheScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        XCTAssertEqual(TVOutputLayout.aspectFitRect(content: CGSize(width: 1920, height: 1080), in: bounds), bounds)
    }

    func testFourByThreeIsPillarboxed() {
        let rect = TVOutputLayout.aspectFitRect(content: CGSize(width: 640, height: 480),
                                                in: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(rect, CGRect(x: 240, y: 0, width: 1440, height: 1080))
    }

    func testWideContentIsLetterboxed() {
        let rect = TVOutputLayout.aspectFitRect(content: CGSize(width: 1920, height: 1080),
                                                in: CGRect(x: 100, y: 50, width: 1600, height: 1200))
        XCTAssertEqual(rect, CGRect(x: 100, y: 200, width: 1600, height: 900))
    }

    func testUnknownContentSizeUsesTheBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(TVOutputLayout.aspectFitRect(content: .zero, in: bounds), bounds)
    }
}
