import XCTest
@testable import CodeIsland

@MainActor
final class PersonalUtilitiesModelTests: XCTestCase {
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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIsland-PersonalUtilities-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
