import AVFoundation
import XCTest
@testable import CodeIslandCompanion

final class AudioSessionPolicyTests: XCTestCase {
    func testAgentOpsVoiceRecordingUsesPhysicalDeviceCompatibleInputSession() {
        let configuration =
            agentOpsVoiceRecordingAudioSessionConfiguration()

        XCTAssertEqual(configuration.category, .playAndRecord)
        XCTAssertEqual(configuration.mode, .measurement)
        XCTAssertTrue(configuration.options.contains(.defaultToSpeaker))
        XCTAssertNotEqual(configuration.mode, .spokenAudio)
    }

    func testSpeakerFirstAddsSpeakerWithoutRemovingWebRTCOptions() {
        let existing: AVAudioSession.CategoryOptions = [
            .allowBluetoothHFP,
            .allowBluetoothA2DP,
            .duckOthers,
        ]

        let result = speakerFirstWebRTCOptions(from: existing)

        XCTAssertTrue(result.contains(.defaultToSpeaker))
        XCTAssertTrue(result.contains(.allowBluetoothHFP))
        XCTAssertTrue(result.contains(.allowBluetoothA2DP))
        XCTAssertTrue(result.contains(.duckOthers))
    }
}
