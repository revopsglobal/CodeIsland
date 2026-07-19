import XCTest
@testable import CodeIsland

final class RemoteBuddyBuildExpectationTests: XCTestCase {
    func testUnconfiguredExpectationDoesNotWarn() {
        let expectation = RemoteBuddyBuildExpectation(expectedVersion: "", expectedBuild: "")

        XCTAssertEqual(expectation.status(for: [device(build: "20260719011702")]), .notConfigured)
    }

    func testMatchedExpectationReportsConfirmedDevice() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let expectation = RemoteBuddyBuildExpectation(expectedVersion: "1.0.0", expectedBuild: "20260719011702")
        let status = expectation.status(for: [device(name: "Greg's iPhone", build: "20260719011702", seenAt: date)])

        XCTAssertEqual(status, .matched(deviceName: "Greg's iPhone", lastSeenAt: date))
    }

    func testStaleExpectationUsesNewestObservedPhysicalBuild() {
        let older = Date(timeIntervalSince1970: 1_800_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_060)
        let expectation = RemoteBuddyBuildExpectation(expectedVersion: "1.0.0", expectedBuild: "20260719011702")
        let status = expectation.status(for: [
            device(name: "Older iPhone", build: "20260718212803", seenAt: older),
            device(name: "Greg's iPhone", build: "20260719005630", seenAt: newer)
        ])

        XCTAssertEqual(
            status,
            .stale(
                expectedVersion: "1.0.0",
                expectedBuild: "20260719011702",
                newestDeviceName: "Greg's iPhone",
                newestVersion: "1.0.0",
                newestBuild: "20260719005630",
                newestLastSeenAt: newer
            )
        )
    }

    func testMissingExpectationReportsWhenNoPhysicalBuildHasRegistered() {
        let expectation = RemoteBuddyBuildExpectation(expectedVersion: "1.0.0", expectedBuild: "20260719011702")
        let status = expectation.status(for: [device(version: nil, build: nil)])

        XCTAssertEqual(status, .missing(expectedVersion: "1.0.0", expectedBuild: "20260719011702"))
    }

    private func device(
        name: String = "iPhone",
        version: String? = "1.0.0",
        build: String?,
        seenAt: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> RemoteApprovalDevice {
        RemoteApprovalDevice(
            id: UUID().uuidString,
            name: name,
            tokenHash: "hash",
            pairedAt: seenAt,
            lastSeenAt: seenAt,
            pushToken: nil,
            pushEnvironment: nil,
            liveActivityPushToStartToken: nil,
            liveActivityUpdateTokens: nil,
            lastLiveActivityReceipt: nil,
            recentLiveActivityReceiptIDs: nil,
            clientVersion: version,
            clientBuild: build
        )
    }
}
