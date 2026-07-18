import Foundation
import XCTest
@testable import CodeIslandCore

final class RemoteServiceStatusTests: XCTestCase {
    func testLegacyStatusWithoutHostAvailabilityFieldsStillDecodes() throws {
        let data = Data(#"{"running":true,"pendingCount":0,"serverName":"Mac","version":1}"#.utf8)
        let status = try JSONDecoder().decode(RemoteServiceStatus.self, from: data)

        XCTAssertTrue(status.running)
        XCTAssertNil(status.hostVersion)
        XCTAssertNil(status.launchAtLoginStatus)
        XCTAssertNil(status.launchAtLoginError)
    }

    func testHostAvailabilityFieldsRoundTrip() throws {
        let status = RemoteServiceStatus(
            running: true,
            pendingCount: 2,
            serverName: "Greg's Mac",
            hostVersion: "1.0.48",
            launchAtLoginStatus: "notFound",
            launchAtLoginError: "Service not found"
        )

        let decoded = try JSONDecoder().decode(
            RemoteServiceStatus.self,
            from: JSONEncoder().encode(status)
        )
        XCTAssertEqual(decoded, status)
    }
}
