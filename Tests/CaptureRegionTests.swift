import XCTest
@testable import GameTranslator

final class CaptureRegionTests: XCTestCase {
    func testDictionaryRoundTripKeepsEnabledFlag() {
        var region = CaptureRegion(name: "Dialog", rect: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.3), color: .green)
        region.isEnabled = false

        let restored = CaptureRegion(from: region.toDictionary())
        XCTAssertEqual(restored, region)
        XCTAssertEqual(restored?.isEnabled, false)
    }

    func testRegionsSavedByOlderVersionsAreEnabled() {
        var dict = CaptureRegion(name: "Old", rect: CGRect(x: 0, y: 0, width: 1, height: 1), color: .blue).toDictionary()
        dict.removeValue(forKey: "enabled")

        XCTAssertEqual(CaptureRegion(from: dict)?.isEnabled, true)
    }
}
