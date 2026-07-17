import XCTest
@testable import CodeIsland

@MainActor
final class PersonalUtilitiesModelTests: XCTestCase {
    func testStartDoesNotBlockOnProtectedDownloadsDirectory() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let openerEntered = expectation(description: "directory opener runs off the main actor")
        let releaseOpener = DispatchSemaphore(value: 0)
        let model = PersonalUtilitiesModel(downloadsURL: directory) { _ in
            openerEntered.fulfill()
            releaseOpener.wait()
            return -1
        }

        let startedAt = Date()
        model.start()
        let startDuration = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(startDuration, 0.1)
        await fulfillment(of: [openerEntered], timeout: 3)
        model.stop()
        releaseOpener.signal()
    }

    func testParsesConnectedBluetoothBatteryLevels() throws {
        let data = Data(
            """
            {
              "SPBluetoothDataType": [{
                "device_connected": [{
                  "AirPods Pro": {
                    "device_batteryLevelLeft": "84%",
                    "device_batteryLevelRight": "79%",
                    "device_batteryLevelCase": "61%"
                  }
                }]
              }]
            }
            """.utf8
        )

        let devices = PersonalUtilitiesModel.parseBluetoothProfiler(data)
        let airPods = try XCTUnwrap(devices.first)

        XCTAssertEqual(airPods.name, "AirPods Pro")
        XCTAssertEqual(airPods.primaryPercent, 61)
        XCTAssertEqual(airPods.levels.map(\.label), ["L", "R", "Case"])
        XCTAssertEqual(airPods.summary, "L 84% · R 79% · Case 61%")
    }

    func testIgnoresConnectedDevicesWithoutBatteryReadings() {
        let data = Data(
            """
            {"SPBluetoothDataType":[{"device_connected":[{"iPhone":{"device_rssi":"-37"}}]}]}
            """.utf8
        )

        XCTAssertTrue(PersonalUtilitiesModel.parseBluetoothProfiler(data).isEmpty)
    }

    func testParsesConnectedAndRememberedBluetoothDevices() throws {
        let data = Data(
            """
            {"SPBluetoothDataType":[{
              "device_connected":[{"Keyboard":{"device_address":"AA:BB:CC:DD:EE:01","device_minorType":"Keyboard"}}],
              "device_not_connected":[{"AirPods":{"device_address":"AA:BB:CC:DD:EE:02","device_minorType":"Headphones"}}]
            }]}
            """.utf8
        )

        let devices = PersonalUtilitiesModel.parseBluetoothDevices(data)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].name, "Keyboard")
        XCTAssertTrue(devices[0].isConnected)
        XCTAssertEqual(devices[1].address, "AA:BB:CC:DD:EE:02")
        XCTAssertFalse(devices[1].isConnected)
    }

    func testParsesHIDBatteryAndSkipsInternalKeyboard() throws {
        let plist: [[String: Any]] = [
            ["Product": "MX Master 3S", "BatteryPercent": 47],
            ["Product": "Apple Internal Keyboard / Trackpad", "BatteryPercent": 100],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        let devices = PersonalUtilitiesModel.parseHIDBatteries(data)

        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].name, "MX Master 3S")
        XCTAssertEqual(devices[0].primaryPercent, 47)
    }

    func testFindsChromePartialDownload() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("Crest-5.0.dmg.crdownload")
        try Data(repeating: 0x2A, count: 1_024).write(to: partial)

        let entries = PersonalUtilitiesModel.scanDownloadEntries(in: directory)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "Crest-5.0.dmg")
        XCTAssertEqual(entries[0].bytesReceived, 1_024)
        XCTAssertNil(entries[0].totalBytes)
    }

    func testReadsSafariDownloadProgressMetadata() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = directory.appendingPathComponent("Video.mp4.download", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let metadata: [String: Any] = [
            "DownloadEntryProgressBytesSoFar": 250,
            "DownloadEntryProgressTotalToLoad": 1_000,
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try plist.write(to: package.appendingPathComponent("Info.plist"))

        let entries = PersonalUtilitiesModel.scanDownloadEntries(in: directory)
        let download = try XCTUnwrap(entries.first)

        XCTAssertEqual(download.name, "Video.mp4")
        XCTAssertEqual(download.bytesReceived, 250)
        XCTAssertEqual(download.totalBytes, 1_000)
        XCTAssertEqual(download.percent, 25)
    }

    func testListsOnlyRecentCompletedDownloadFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let completed = directory.appendingPathComponent("handoff.pdf")
        let partial = directory.appendingPathComponent("video.mp4.crdownload")
        let old = directory.appendingPathComponent("old.zip")
        let folder = directory.appendingPathComponent("Folder", isDirectory: true)
        let symlink = directory.appendingPathComponent("linked-hosts.txt")
        try Data("ready".utf8).write(to: completed)
        try Data("partial".utf8).write(to: partial)
        try Data("old".utf8).write(to: old)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-(8 * 24 * 60 * 60))],
            ofItemAtPath: old.path
        )

        let entries = PersonalUtilitiesModel.scanRecentDownloadEntries(in: directory)

        XCTAssertEqual(entries.map(\.name), ["handoff.pdf"])
        XCTAssertEqual(entries.first?.bytes, 5)
        XCTAssertTrue(try XCTUnwrap(entries.first).isTransferable)
    }

    func testRecentCompletedDownloadOverTransferLimitIsNotTransferable() {
        let entry = PersonalUtilitiesModel.RecentDownloadInfo(
            id: "large",
            url: URL(fileURLWithPath: "/tmp/large.dmg"),
            name: "large.dmg",
            bytes: PersonalUtilitiesModel.maximumRemoteTransferBytes + 1,
            modifiedAt: Date()
        )

        XCTAssertFalse(entry.isTransferable)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIsland-PersonalUtilities-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
