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
        XCTAssertTrue(configuration.options.contains(.allowBluetoothHFP))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothA2DP))
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

    func testAgentOpsVoicePlaybackSpeakerSupportsExternalRoutes() {
        let configuration = agentOpsVoicePlaybackAudioSessionConfiguration(
            preference: .speaker
        )

        XCTAssertEqual(configuration.category, .playAndRecord)
        XCTAssertEqual(configuration.mode, .voiceChat)
        XCTAssertTrue(configuration.options.contains(.defaultToSpeaker))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothHFP))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothA2DP))
        XCTAssertTrue(configuration.options.contains(.allowAirPlay))
    }

    func testAgentOpsVoicePlaybackReceiverDoesNotForceSpeaker() {
        let configuration = agentOpsVoicePlaybackAudioSessionConfiguration(
            preference: .receiver
        )

        XCTAssertEqual(configuration.category, .playAndRecord)
        XCTAssertEqual(configuration.mode, .voiceChat)
        XCTAssertFalse(configuration.options.contains(.defaultToSpeaker))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothHFP))
        XCTAssertTrue(configuration.options.contains(.allowBluetoothA2DP))
        XCTAssertTrue(configuration.options.contains(.allowAirPlay))
    }

    func testExternalRouteIsNotOverriddenBySpeakerPreference() {
        for route in [
            AgentOpsAudioRouteKind.bluetooth,
            .airplay,
            .headphones,
        ] {
            XCTAssertFalse(
                agentOpsVoiceShouldOverrideSpeaker(
                    preference: .speaker,
                    currentRoute: route
                )
            )
        }
    }

    func testBuiltInRouteHonorsSpeakerPreference() {
        XCTAssertTrue(
            agentOpsVoiceShouldOverrideSpeaker(
                preference: .speaker,
                currentRoute: .receiver
            )
        )
        XCTAssertFalse(
            agentOpsVoiceShouldOverrideSpeaker(
                preference: .receiver,
                currentRoute: .speaker
            )
        )
    }
}
