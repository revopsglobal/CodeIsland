import Foundation
import XCTest
@testable import CodeIslandCompanion

final class VoiceSessionReducerTests: XCTestCase {
    func testRealtimeSurfaceContainsOnlyAgentOpsTurnAndRequiresItForEveryTurn() {
        XCTAssertEqual(AgentOpsRealtimeProtocol.toolDefinitions.map(\.name), ["agentops_turn"])
        XCTAssertTrue(
            AgentOpsRealtimeProtocol.instructions.contains(
                "For every semantic user turn, call agentops_turn exactly once"
            )
        )
        XCTAssertTrue(
            AgentOpsRealtimeProtocol.instructions.contains(
                "Do not independently answer operational"
            )
        )
    }

    func testDuplicateCallIDExecutesExactlyOnce() {
        var state = VoiceSessionState()
        let event = VoiceSessionEvent.server(
            .functionCallArgumentsDone(
                callId: "call-1",
                name: "agentops_turn",
                argumentsJSON: #"{"transcript":"Ship the fix"}"#
            )
        )

        let first = VoiceSessionReducer.reduce(&state, event)
        let duplicate = VoiceSessionReducer.reduce(&state, event)

        XCTAssertEqual(
            first,
            [.executeTurn(
                callId: "call-1",
                argumentsJSON: #"{"transcript":"Ship the fix"}"#
            )]
        )
        XCTAssertFalse(duplicate.contains { effect in
            if case .executeTurn = effect { return true }
            return false
        })
        XCTAssertEqual(state.pendingCalls.map(\.callId), ["call-1"])
    }

    func testToolOutputIsSentBeforeRealtimeIsAskedToSpeak() {
        var state = VoiceSessionState()
        _ = VoiceSessionReducer.reduce(&state, .callEstablished)
        _ = VoiceSessionReducer.reduce(
            &state,
            .server(
                .functionCallArgumentsDone(
                    callId: "call-2",
                    name: "agentops_turn",
                    argumentsJSON: #"{"transcript":"What is current?"}"#
                )
            )
        )

        let effects = VoiceSessionReducer.reduce(
            &state,
            .toolResultReady(callId: "call-2", outputJSON: #"{"kind":"answer"}"#)
        )

        XCTAssertEqual(effects, [
            .send(.functionCallOutput(
                callId: "call-2",
                outputJSON: #"{"kind":"answer"}"#
            )),
            .send(.responseCreate),
        ])
    }

    func testBargeInCancelsResponseAndClearsBufferedAudio() {
        var state = VoiceSessionState()
        _ = VoiceSessionReducer.reduce(&state, .callEstablished)
        _ = VoiceSessionReducer.reduce(
            &state,
            .server(.responseCreated(responseId: "response-1"))
        )

        let effects = VoiceSessionReducer.reduce(
            &state,
            .server(.inputAudioBufferSpeechStarted)
        )

        XCTAssertEqual(state.phase, .userSpeaking)
        XCTAssertNil(state.activeResponseId)
        XCTAssertEqual(effects, [
            .send(.responseCancel(responseId: "response-1")),
            .send(.outputAudioBufferClear),
        ])
    }

    func testPauseDisablesMicrophoneAndDefersSpeechUntilResume() {
        var state = VoiceSessionState()
        _ = VoiceSessionReducer.reduce(&state, .callEstablished)
        _ = VoiceSessionReducer.reduce(
            &state,
            .server(.responseCreated(responseId: "response-2"))
        )

        let pause = VoiceSessionReducer.reduce(&state, .pauseRequested)
        let resultWhilePaused = VoiceSessionReducer.reduce(
            &state,
            .toolResultReady(callId: "call-3", outputJSON: #"{"kind":"answer"}"#)
        )
        let resume = VoiceSessionReducer.reduce(&state, .resumeRequested)

        XCTAssertEqual(pause, [
            .setMicrophoneEnabled(false),
            .send(.responseCancel(responseId: "response-2")),
            .send(.outputAudioBufferClear),
        ])
        XCTAssertEqual(resultWhilePaused, [
            .send(.functionCallOutput(
                callId: "call-3",
                outputJSON: #"{"kind":"answer"}"#
            )),
        ])
        XCTAssertEqual(resume, [
            .setMicrophoneEnabled(true),
            .send(.responseCreate),
        ])
    }
}
