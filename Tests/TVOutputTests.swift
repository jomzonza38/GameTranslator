import XCTest
import CoreGraphics
@testable import GameTranslator

/// AC-1 (T-0027): capture format choice, output display choice, aspect-fit rect,
/// capture card / audio device matching
final class TVOutputTests: XCTestCase {
    private let usb = CaptureCardSelection.fourCC("usb ")
    private let builtIn = CaptureCardSelection.builtInTransport
    private let virtual = CaptureCardSelection.virtualTransport

    private func format(_ w: Int, _ h: Int, _ fps: Double, _ fourCC: String, minFPS: Double = 5) -> CaptureFormatCandidate {
        CaptureFormatCandidate(width: w, height: h, frameRateRanges: [minFPS...fps], fourCC: fourCC)
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

    func testFrameRateCapsAtSixty() {
        XCTAssertEqual(CaptureCardSelection.frameRate(for: format(1920, 1080, 120, "jpeg")), 60)
        XCTAssertEqual(CaptureCardSelection.frameRate(for: format(1920, 1080, 60, "jpeg")), 60)
        XCTAssertEqual(CaptureCardSelection.frameRate(for: format(1920, 1080, 30, "jpeg")), 30)
        // Only a fixed high rate offered: use it
        XCTAssertEqual(CaptureCardSelection.frameRate(for: format(1920, 1080, 120, "jpeg", minFPS: 120)), 120)
    }

    func testDescription() {
        XCTAssertEqual(CaptureCardSelection.describe(format(1920, 1080, 60, "jpeg"), frameRate: 60),
                       "1920×1080 @ 60 fps · MJPEG")
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
