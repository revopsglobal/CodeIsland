import Foundation
import XCTest

final class MediaEntitlementTests: XCTestCase {
    func testHardenedMacAppDeclaresCameraAndAudioInputEntitlements() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementURL = repoRoot.appendingPathComponent("CodeIsland.entitlements")
        let data = try Data(contentsOf: entitlementURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["com.apple.security.device.camera"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.device.audio-input"] as? Bool, true)
    }
}
