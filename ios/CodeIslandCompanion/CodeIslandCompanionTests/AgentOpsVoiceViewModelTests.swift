import XCTest
@testable import CodeIslandCompanion

@MainActor
final class AgentOpsVoiceViewModelTests: XCTestCase {
    func testEveryRequiredVoiceStateHasAStableAccessibleLabel() {
        let expectations: [(AgentOpsVoiceMockScenario, VoiceSessionPhase, String)] = [
            (.listening, .listening, "Recording"),
            (.userSpeaking, .userSpeaking, "Recording"),
            (.thinking, .thinking, "Transcribing"),
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

    func testOneRecordingProducesOneTurnAndNeverRestartsTheMicrophone() async {
        let events = VoiceTestEvents()
        let audio = FakeVoiceAudio(events: events)
        let service = FakeVoiceService(events: events)
        let model = AgentOpsVoiceViewModel(
            audioController: audio,
            service: service
        )

        await model.startVoice()
        XCTAssertTrue(model.isRecording)
        model.finishRecording()
        await waitUntil { model.phase == .idle && !model.isRunning }

        XCTAssertEqual(events.values, [
            "audio.start",
            "audio.stop",
            "service.transcribe",
            "service.turn",
            "service.speech",
            "audio.play",
        ])
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(service.transcripts, ["Canonical AgentOps request."])
        XCTAssertEqual(
            model.transcriptEntries.map(\.role),
            [.user, .assistant]
        )
        XCTAssertEqual(model.latestResult?.speechText, "Canonical answer.")
        XCTAssertFalse(model.isRecording)
    }

    func testMicrophoneStaysOffForEntirePlaybackAndNeedsAnotherTap() async {
        let events = VoiceTestEvents()
        let audio = FakeVoiceAudio(events: events, suspendPlayback: true)
        let service = FakeVoiceService(events: events)
        let model = AgentOpsVoiceViewModel(
            audioController: audio,
            service: service
        )

        await model.startVoice()
        model.finishRecording()
        await waitUntil { model.phase == .speaking && audio.isPlaying }

        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(audio.startCount, 1)
        XCTAssertEqual(events.values.filter { $0 == "service.turn" }.count, 1)

        audio.completePlayback()
        await waitUntil { model.phase == .idle && !model.isRunning }

        XCTAssertEqual(audio.startCount, 1)
        XCTAssertTrue(model.canStart)
        XCTAssertEqual(events.values.filter { $0 == "service.turn" }.count, 1)
    }

    func testTranscriptionFailureCannotCreateAnAgentOpsTurnOrSpeech() async {
        let events = VoiceTestEvents()
        let audio = FakeVoiceAudio(events: events)
        let service = FakeVoiceService(
            events: events,
            failure: .transcription
        )
        let model = AgentOpsVoiceViewModel(
            audioController: audio,
            service: service
        )

        await model.startVoice()
        model.finishRecording()
        await waitUntil {
            if case .failed = model.phase { return true }
            return false
        }

        XCTAssertEqual(events.values, [
            "audio.start",
            "audio.stop",
            "service.transcribe",
        ])
        XCTAssertTrue(service.transcripts.isEmpty)
        XCTAssertNil(model.latestResult)
        XCTAssertFalse(model.isRecording)
    }

    func testCancelDuringPlaybackCreatesAContentFreePhysicalReceipt() async {
        let events = VoiceTestEvents()
        let audio = FakeVoiceAudio(events: events, suspendPlayback: true)
        let journal = receiptJournal()
        let model = AgentOpsVoiceViewModel(
            audioController: audio,
            service: FakeVoiceService(events: events),
            receiptJournal: journal
        )

        await model.startVoice()
        model.finishRecording()
        await waitUntil { model.phase == .speaking && audio.isPlaying }
        model.stopResponse()

        XCTAssertEqual(
            journal.pending.map(\.kind),
            [.voicePlaybackCancelled]
        )
        XCTAssertEqual(journal.pending.first?.sessionId != nil, true)
        XCTAssertEqual(model.phase, .idle)
    }

    func testBackgroundingStopsAudioAndReturnsToReadyOnForeground() async {
        let events = VoiceTestEvents()
        let audio = FakeVoiceAudio(events: events)
        let journal = receiptJournal()
        let model = AgentOpsVoiceViewModel(
            audioController: audio,
            service: FakeVoiceService(events: events),
            receiptJournal: journal
        )

        await model.startVoice()
        model.setSceneActive(false)

        XCTAssertEqual(model.phase, .paused)
        XCTAssertFalse(model.isRecording)
        XCTAssertFalse(model.isRunning)
        XCTAssertEqual(
            journal.pending.map(\.kind),
            [.voiceBackgroundCancelled]
        )

        model.resumeFromBackground()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertTrue(model.canStart)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for voice state")
    }

    private func receiptJournal() -> AgentOpsMobileReceiptJournal {
        let suite = "AgentOpsVoiceViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AgentOpsMobileReceiptJournal(
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            now: { Date(timeIntervalSince1970: 1_785_260_083) },
            clientProvider: {
                AgentOpsMobileClientSnapshot(
                    appVersion: "1.0.0",
                    build: "test",
                    osVersion: "26.5",
                    deviceModel: "iPhone17,1"
                )
            }
        )
    }
}

@MainActor
private final class VoiceTestEvents {
    var values: [String] = []
}

@MainActor
private final class FakeVoiceAudio: AgentOpsVoiceAudioHandling {
    let events: VoiceTestEvents
    let suspendPlayback: Bool
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private(set) var startCount = 0
    private(set) var isPlaying = false
    private(set) var outputPreference: AgentOpsVoiceOutputPreference = .speaker
    private(set) var currentRoute: AgentOpsAudioRouteKind = .speaker
    private var routeChangeHandler:
        (@MainActor (AgentOpsAudioRouteKind) -> Void)?

    init(events: VoiceTestEvents, suspendPlayback: Bool = false) {
        self.events = events
        self.suspendPlayback = suspendPlayback
    }

    func startRecording() async throws {
        startCount += 1
        events.values.append("audio.start")
    }

    func stopRecording() throws -> AgentOpsVoiceRecording {
        events.values.append("audio.stop")
        return AgentOpsVoiceRecording(
            data: Data([1, 2, 3]),
            contentType: "audio/m4a"
        )
    }

    func play(_ audio: Data) async throws {
        events.values.append("audio.play")
        guard suspendPlayback else { return }
        isPlaying = true
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
        }
    }

    func completePlayback() {
        isPlaying = false
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    func setOutputPreference(_ preference: AgentOpsVoiceOutputPreference) {
        outputPreference = preference
        currentRoute = preference == .speaker ? .speaker : .receiver
        routeChangeHandler?(currentRoute)
    }

    func setRouteChangeHandler(
        _ handler: @escaping @MainActor (AgentOpsAudioRouteKind) -> Void
    ) {
        routeChangeHandler = handler
    }

    func cancel() {
        isPlaying = false
        playbackContinuation?.resume(throwing: CancellationError())
        playbackContinuation = nil
    }
}

private enum FakeVoiceFailure: Error {
    case transcription
}

@MainActor
private final class FakeVoiceService: AgentOpsVoiceServicing {
    let events: VoiceTestEvents
    let failure: FakeVoiceFailure?
    private(set) var transcripts: [String] = []

    init(
        events: VoiceTestEvents,
        failure: FakeVoiceFailure? = nil
    ) {
        self.events = events
        self.failure = failure
    }

    func transcribe(
        _ recording: AgentOpsVoiceRecording
    ) async throws -> String {
        events.values.append("service.transcribe")
        if failure == .transcription {
            throw FakeVoiceFailure.transcription
        }
        return "Canonical AgentOps request."
    }

    func executeTurn(
        transcript: String
    ) async throws -> AgentOpsTurnExecution {
        transcripts.append(transcript)
        events.values.append("service.turn")
        return makeVoiceExecution()
    }

    func synthesize(_ text: String) async throws -> Data {
        events.values.append("service.speech")
        return Data([4, 5, 6])
    }
}

private func makeVoiceExecution() -> AgentOpsTurnExecution {
    let sessionID = UUID(
        uuidString: "11111111-1111-4111-8111-111111111111"
    )!
    let turnID = UUID(
        uuidString: "22222222-2222-4222-8222-222222222222"
    )!
    let request = AgentOpsTurnRequest(
        sessionID: sessionID,
        turnID: turnID,
        idempotencyKey: turnID,
        transcript: "Canonical AgentOps request.",
        conversation: [],
        client: AgentOpsClientMetadata(
            platform: "ios",
            appVersion: "1.0",
            build: "test",
            locale: "en-US"
        )
    )
    let result = AgentOpsTurnResult(
        kind: .answer,
        speechText: "Canonical answer.",
        displayText: "Canonical answer.",
        sources: [],
        routingIntent: AgentOpsTurnRoutingIntent(
            mode: .auto,
            implementer: nil,
            reviewer: nil,
            allowFallback: false,
            fallbackRuntime: nil,
            reason: "Answer only."
        ),
        approvalTier: .routineVoice,
        executionBrief: nil,
        task: nil,
        unavailableSources: []
    )
    return AgentOpsTurnExecution(
        request: request,
        result: result,
        outputJSON: "{}"
    )
}
