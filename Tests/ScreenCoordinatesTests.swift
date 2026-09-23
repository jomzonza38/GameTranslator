import XCTest
@testable import GameTranslator

/// Layout used below (CG coordinates, y down):
///   primary   1440×900  at (0, 0)
///   secondary 2560×1440 to its right, top edges aligned: (1440, 0)
/// In AppKit coordinates (y up, origin bottom-left of primary) the secondary is at
/// (1440, 900 - 1440 = -540).
final class ScreenCoordinatesTests: XCTestCase {
    private let primaryHeight: CGFloat = 900
    private let primaryAppKit = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let secondaryAppKit = CGRect(x: 1440, y: -540, width: 2560, height: 1440)

    func testRectOnPrimaryDisplay() {
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        XCTAssertEqual(
            ScreenCoordinates.appKitRect(fromCG: cg, primaryDisplayHeight: primaryHeight),
            CGRect(x: 100, y: 250, width: 800, height: 600)
        )
    }

    func testRectOnTallerSecondaryDisplay() {
        // Game window near the top of the secondary display
        let cg = CGRect(x: 1600, y: 100, width: 800, height: 600)
        let appKit = ScreenCoordinates.appKitRect(fromCG: cg, primaryDisplayHeight: primaryHeight)

        XCTAssertEqual(appKit, CGRect(x: 1600, y: 200, width: 800, height: 600))
        XCTAssertTrue(secondaryAppKit.contains(appKit))
        // Using the secondary's height (what NSScreen.main gave when it had focus)
        // would put it 540 pt too high
        XCTAssertNotEqual(
            appKit,
            ScreenCoordinates.appKitRect(fromCG: cg, primaryDisplayHeight: secondaryAppKit.height)
        )
    }

    func testRectLowOnSecondaryDisplayBelowPrimaryBottom() {
        // Below the primary display's bottom edge → negative AppKit y
        let cg = CGRect(x: 2000, y: 1000, width: 400, height: 300)
        let appKit = ScreenCoordinates.appKitRect(fromCG: cg, primaryDisplayHeight: primaryHeight)
        XCTAssertEqual(appKit, CGRect(x: 2000, y: -400, width: 400, height: 300))
        XCTAssertTrue(secondaryAppKit.contains(appKit))
    }

    func testScreenShowingMostOfRect() {
        let screens = [primaryAppKit, secondaryAppKit]
        let onSecondary = CGRect(x: 1600, y: 200, width: 800, height: 600)
        XCTAssertEqual(ScreenCoordinates.indexOfScreen(showingMostOf: onSecondary, screenFrames: screens), 1)

        let onPrimary = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(ScreenCoordinates.indexOfScreen(showingMostOf: onPrimary, screenFrames: screens), 0)

        // Spanning both: 200 pt on primary, 600 pt on secondary → secondary
        let spanning = CGRect(x: 1240, y: 100, width: 800, height: 400)
        XCTAssertEqual(ScreenCoordinates.indexOfScreen(showingMostOf: spanning, screenFrames: screens), 1)

        let offScreen = CGRect(x: -5000, y: -5000, width: 100, height: 100)
        XCTAssertNil(ScreenCoordinates.indexOfScreen(showingMostOf: offScreen, screenFrames: screens))
    }
}
