import Foundation
import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class PersonalHubConfigurationStoreTests: XCTestCase {
    func testPersistsSanitizedRacksAndDashboardAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandHubConfiguration-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("configuration.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PersonalHubConfigurationStore(stateURL: stateURL)
        try store.updateRack(mode: .work, modules: [.notes, .calendar, .notes])
        try store.setDashboardEnabled(false)

        let restarted = PersonalHubConfigurationStore(stateURL: stateURL)
        XCTAssertEqual(Array(restarted.configuration.rack(for: .work).prefix(2)), [.notes, .calendar])
        XCTAssertEqual(restarted.configuration.rack(for: .work), [.notes, .calendar])
        XCTAssertFalse(restarted.configuration.dashboardEnabled)
    }

    func testRejectsAutoAsPersistedRack() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandHubConfiguration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalHubConfigurationStore(
            stateURL: directory.appendingPathComponent("configuration.json")
        )

        XCTAssertThrowsError(try store.updateRack(mode: .auto, modules: [.notes]))
    }

    func testServiceAppliesExactConfirmedRackAndDashboardMutations() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandHubConfiguration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalHubConfigurationStore(
            stateURL: directory.appendingPathComponent("configuration.json")
        )
        let service = PersonalHubService(configurationStore: store)
        let rackMutation = PersonalHubConfigurationMutation(
            mode: .code,
            modules: [.claude, .agents]
        )
        let rackIntent = PersonalHubActionIntent(
            moduleID: .quickToggles,
            actionID: "setModeRack",
            value: try XCTUnwrap(rackMutation.encodedActionValue())
        )
        let prepared = try XCTUnwrap(try service.prepare(
            intent: rackIntent,
            deviceID: "test-device"
        ).get())

        XCTAssertTrue(try service.execute(
            request: .init(intent: rackIntent, actionToken: prepared.actionToken),
            deviceID: "test-device"
        ).get().executed)
        XCTAssertEqual(store.configuration.rack(for: .code), [.claude, .agents])

        let dashboardIntent = PersonalHubActionIntent(
            moduleID: .quickToggles,
            actionID: "setDashboard",
            value: PersonalHubConfigurationMutation(dashboardEnabled: false).encodedActionValue()
        )
        let dashboardPrepared = try XCTUnwrap(try service.prepare(
            intent: dashboardIntent,
            deviceID: "test-device"
        ).get())
        _ = try service.execute(
            request: .init(intent: dashboardIntent, actionToken: dashboardPrepared.actionToken),
            deviceID: "test-device"
        ).get()
        XCTAssertFalse(store.configuration.dashboardEnabled)
    }
}
