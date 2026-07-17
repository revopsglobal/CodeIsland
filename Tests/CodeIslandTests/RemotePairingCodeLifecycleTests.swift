import Foundation
import XCTest
@testable import CodeIsland

@MainActor
final class RemotePairingCodeLifecycleTests: XCTestCase {
    func testExpiredCodeIsReplacedWhenPairingSurfaceBecomesVisible() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandPairingLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RemoteApprovalDeviceStore(
            stateURL: directory.appendingPathComponent("devices.json")
        )
        let expiredAt = store.pairingExpiresAt.addingTimeInterval(1)

        XCTAssertTrue(store.ensureActivePairingCode(at: expiredAt))
        XCTAssertEqual(store.pairingExpiresAt.timeIntervalSince(expiredAt), 600, accuracy: 0.01)
    }

    func testActiveCodeIsNotRotatedWhilePairingSurfaceRemainsVisible() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandPairingLifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = RemoteApprovalDeviceStore(
            stateURL: directory.appendingPathComponent("devices.json")
        )
        let code = store.pairingCode
        let oneSecondBeforeExpiry = store.pairingExpiresAt.addingTimeInterval(-1)

        XCTAssertFalse(store.ensureActivePairingCode(at: oneSecondBeforeExpiry))
        XCTAssertEqual(store.pairingCode, code)
    }
}
