import XCTest
@testable import CodeIsland

final class PersonalHubDataModelTests: XCTestCase {
    func testParsesMacBattery() {
        let output = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=123)\t87%; charging; 0:42 remaining present: true
        """

        let battery = PersonalHubDataModel.parseMacBattery(output)

        XCTAssertEqual(battery?.percent, 87)
        XCTAssertEqual(battery?.status, "charging")
        XCTAssertEqual(battery?.powerSource, "AC Power")
    }

    func testParsesVMStatMemoryUsage() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages free:                               1000.
        Pages active:                             5000.
        Pages speculative:                         250.
        """

        let used = PersonalHubDataModel.parseVMStat(output, totalBytes: 10_000_000)

        XCTAssertEqual(used, 4_880_000)
    }

    func testParsesAudioInputsOutputsAndDefaults() throws {
        let data = try XCTUnwrap("""
        {
          "SPAudioDataType": [{
            "_items": [
              {"_name":"MacBook Speakers","coreaudio_device_output":2,"coreaudio_output_source":"spaudio_default"},
              {"_name":"USB Mic","coreaudio_device_input":1,"coreaudio_input_source":"spaudio_default"}
            ]
          }]
        }
        """.data(using: .utf8))

        let devices = PersonalHubDataModel.parseAudioDevices(data)

        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(try XCTUnwrap(devices.first(where: { $0.name == "MacBook Speakers" })).isDefaultOutput)
        XCTAssertTrue(try XCTUnwrap(devices.first(where: { $0.name == "USB Mic" })).isDefaultInput)
    }
}
