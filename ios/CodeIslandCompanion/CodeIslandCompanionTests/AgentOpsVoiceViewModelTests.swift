import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsVoiceViewModelTests: XCTestCase {
    func testEveryRequiredVoiceStateHasAStableAccessibleLabel() {
        let expectations: [(AgentOpsVoiceMockScenario, VoiceSessionPhase, String)] = [
            (.listening, .listening, "Listening"),
            (.userSpeaking, .userSpeaking, "You are speaking"),
            (.thinking, .thinking, "Thinking"),
            (.toolWorking, .toolWorking, "Working in AgentOps"),
            (.speaking, .speaking, "Speaking"),
            (.reconnecting, .reconnecting, "Reconnecting"),
            (.paused, .paused, "Paused"),
            (.failed, .failed("AgentOps is temporarily unavailable."), "Needs attention"),
        ]

        for (scenario, phase, label) in expectations {
            let model = AgentOpsVoiceViewModel(mockScenario: scenario)
            XCTAssertEqual(model.phase, phase)
            XCTAssertEqual(model.stateTitle, label)
        }
    }

    func testDurableWorkPublishesCanonicalTaskUUIDImmediately() {
        let model = AgentOpsVoiceViewModel(mockScenario: .durable)

        XCTAssertEqual(model.latestResult?.kind, .durableWork)
        XCTAssertEqual(
            model.latestResult?.task?.id.uuidString.lowercased(),
            "e7e843c5-733d-4492-a863-1c337684653b"
        )
        XCTAssertEqual(model.latestResult?.sources.first?.label, "AgentOps task")
    }

    func testAnswerClarificationAndDurableWorkRemainDistinct() {
        XCTAssertEqual(
            AgentOpsVoiceViewModel(mockScenario: .answer).latestResult?.kind,
            .answer
        )
        XCTAssertEqual(
            AgentOpsVoiceViewModel(mockScenario: .clarify).latestResult?.kind,
            .clarify
        )
        XCTAssertEqual(
            AgentOpsVoiceViewModel(mockScenario: .durable).latestResult?.kind,
            .durableWork
        )
    }

    func testMuteAndStopRemainIndependentControls() {
        let model = AgentOpsVoiceViewModel(mockScenario: .speaking)

        XCTAssertTrue(model.canStop)
        XCTAssertFalse(model.isMuted)
        model.toggleMute()

        XCTAssertTrue(model.isMuted)
        XCTAssertTrue(model.canStop)
    }
}
