import Combine
import Foundation

enum AgentOpsVoiceMockScenario: String, CaseIterable, Sendable {
    case listening
    case userSpeaking = "user-speaking"
    case thinking
    case toolWorking = "tool-working"
    case speaking
    case reconnecting
    case paused
    case failed
    case answer
    case clarify
    case durable
    case offlineDraft = "offline-draft"
    case realtimeUnavailable = "realtime-unavailable"
    case gatewayUnavailable = "gateway-unavailable"
    case claudeUnavailable = "claude-unavailable"
    case contextUnavailable = "context-unavailable"
    case captureUnavailable = "capture-unavailable"
    case lockedWorkerUnavailable = "locked-worker-unavailable"
    case failedVerification = "failed-verification"

    static func from(arguments: [String]) -> AgentOpsVoiceMockScenario? {
        guard
            let index = arguments.firstIndex(of: "-AgentOpsVoiceMock"),
            arguments.indices.contains(index + 1)
        else { return nil }
        return AgentOpsVoiceMockScenario(
            rawValue: arguments[index + 1].lowercased()
        )
    }
}

@MainActor
final class AgentOpsVoiceViewModel: ObservableObject {
    @Published private(set) var phase: VoiceSessionPhase = .idle
    @Published private(set) var transcriptEntries: [VoiceTranscriptEntry] = []
    @Published private(set) var latestResult: AgentOpsTurnResult?
    @Published private(set) var isMuted = false
    @Published private(set) var isRunning = false

    let mockScenario: AgentOpsVoiceMockScenario?

    private var sessionState = VoiceSessionState()
    private var coordinator: VoiceSessionCoordinator?
    private var turnTool: AgentOpsTurnTool?
    private weak var rootStore: AgentOpsRootStore?
    private let sessionID = UUID()
    private var liveAssistantEntryID: UUID?

    init(mockScenario: AgentOpsVoiceMockScenario? = nil) {
        self.mockScenario = mockScenario
        if let mockScenario {
            applyMock(mockScenario)
        }
    }

    var isMock: Bool { mockScenario != nil }

    var stateTitle: String {
        switch phase {
        case .idle: return "Ready"
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .userSpeaking: return "You are speaking"
        case .thinking: return "Thinking"
        case .toolWorking: return "Working in AgentOps"
        case .speaking: return "Speaking"
        case .reconnecting: return "Reconnecting"
        case .paused: return "Paused"
        case .failed: return "Needs attention"
        }
    }

    var stateDetail: String {
        switch phase {
        case .idle:
            return "Tap Start voice when you are ready."
        case .connecting:
            return "Opening a private realtime session."
        case .listening:
            return "Ask about the Wiki, work, repos, or create a task."
        case .userSpeaking:
            return "I’m listening to your request."
        case .thinking:
            return "AgentOps is choosing the right response path."
        case .toolWorking:
            return "AgentOps is loading context and capturing durable work."
        case .speaking:
            return "The answer came from AgentOps."
        case .reconnecting:
            return "Restoring the private voice session."
        case .paused:
            return "Microphone and assistant audio are paused."
        case .failed(let message):
            return message
        }
    }

    var canStop: Bool {
        switch phase {
        case .thinking, .toolWorking, .speaking:
            return true
        default:
            return false
        }
    }

    func configure(rootStore: AgentOpsRootStore) {
        self.rootStore = rootStore
        guard !isMock, coordinator == nil, let client = rootStore.client else {
            return
        }

        let tool = AgentOpsTurnTool(
            client: client,
            sessionID: sessionID,
            clientMetadata: .current(),
            draftStore: rootStore.draftStore
        )
        let coordinator = VoiceSessionCoordinator(
            credentialProvider: { voice in
                try await client.mintRealtimeCredential(voice: voice)
            },
            makeTransport: {
                AgentOpsRealtimeTransport(
                    engine: makeAgentOpsWebRTCEngine()
                )
            }
        )
        coordinator.onServerEvent = { [weak self] event in
            self?.receive(event)
        }
        coordinator.onCallEstablished = { [weak self] in
            self?.apply(.callEstablished)
        }
        coordinator.onDisconnected = { [weak self] reason in
            self?.apply(.transportDisconnected(reason: reason))
        }
        self.turnTool = tool
        self.coordinator = coordinator
    }

    func startVoice() async {
        guard !isMock else {
            isRunning = true
            return
        }
        guard let coordinator else {
            phase = .failed("AgentOps voice is not configured in this build.")
            return
        }
        guard !isRunning else { return }
        isRunning = true
        phase = .connecting
        let result = await coordinator.start(voice: nil)
        if case .failure(let message) = result {
            apply(.callEstablishmentFailed(safeConnectionMessage(message)))
        }
    }

    func endVoice() async {
        guard !isMock else {
            isRunning = false
            phase = .idle
            return
        }
        await coordinator?.teardown()
        sessionState = VoiceSessionState()
        phase = .idle
        isMuted = false
        isRunning = false
        liveAssistantEntryID = nil
    }

    func stopResponse() {
        guard !isMock else { return }
        apply(.stopRequested)
    }

    func toggleMute() {
        guard !isMock else {
            isMuted.toggle()
            return
        }
        if isMuted {
            apply(.resumeRequested)
        } else {
            apply(.pauseRequested)
        }
        isMuted.toggle()
    }

    private func receive(_ event: RealtimeServerEvent) {
        if case .responseAudioTranscriptDelta(let delta) = event {
            appendAssistantDelta(delta)
        }
        if case .responseDone = event {
            liveAssistantEntryID = nil
        }
        apply(.server(event))
    }

    private func apply(_ event: VoiceSessionEvent) {
        let effects = VoiceSessionReducer.reduce(&sessionState, event)
        phase = sessionState.phase
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: VoiceSessionEffect) {
        switch effect {
        case .send(let event):
            do {
                try coordinator?.send(event)
            } catch {
                apply(
                    .transportDisconnected(
                        reason: "The realtime session disconnected."
                    )
                )
            }

        case .setMicrophoneEnabled(let enabled):
            coordinator?.setMicrophoneEnabled(enabled)

        case .executeTurn(let callId, let argumentsJSON):
            appendUserTranscript(from: argumentsJSON)
            Task { @MainActor [weak self] in
                guard let self, let turnTool = self.turnTool else { return }
                do {
                    let execution = try await turnTool.execute(
                        callId: callId,
                        argumentsJSON: argumentsJSON
                    )
                    self.latestResult = execution.result
                    self.rootStore?.recordTurnResult(execution.result)
                    self.apply(
                        .toolResultReady(
                            callId: callId,
                            outputJSON: execution.outputJSON
                        )
                    )
                } catch {
                    if self.rootStore?.draftStore?.drafts.isEmpty == false {
                        self.transcriptEntries.append(
                            VoiceTranscriptEntry(
                                role: .system,
                                text: "Saved privately on this iPhone. It will retry with the same request identity when AgentOps reconnects."
                            )
                        )
                    }
                    self.apply(
                        .toolExecutionFailed(
                            callId: callId,
                            message: "AgentOps could not complete this turn."
                        )
                    )
                }
            }

        case .scheduleReconnect(let delay):
            coordinator?.scheduleReconnect(
                after: delay,
                voice: nil
            ) { [weak self] result in
                switch result {
                case .success:
                    break
                case .failure(let message):
                    self?.apply(
                        .callEstablishmentFailed(
                            self?.safeConnectionMessage(message)
                                ?? "AgentOps could not reconnect."
                        )
                    )
                }
            }

        case .log:
            break
        }
    }

    private func appendUserTranscript(from argumentsJSON: String) {
        struct Arguments: Decodable { let transcript: String }
        guard
            let data = argumentsJSON.data(using: .utf8),
            let value = try? JSONDecoder().decode(Arguments.self, from: data),
            !value.transcript.isEmpty
        else { return }
        transcriptEntries.append(
            VoiceTranscriptEntry(role: .user, text: value.transcript)
        )
    }

    private func appendAssistantDelta(_ delta: String) {
        guard !delta.isEmpty else { return }
        if let id = liveAssistantEntryID,
           let index = transcriptEntries.firstIndex(where: { $0.id == id }) {
            transcriptEntries[index].text += delta
        } else {
            let entry = VoiceTranscriptEntry(role: .assistant, text: delta)
            liveAssistantEntryID = entry.id
            transcriptEntries.append(entry)
        }
    }

    private func safeConnectionMessage(_ message: String) -> String {
        guard !message.isEmpty else {
            return "AgentOps could not open the voice session."
        }
        return "AgentOps could not open the voice session. Try again."
    }

    private func applyMock(_ scenario: AgentOpsVoiceMockScenario) {
        isRunning = true
        switch scenario {
        case .listening:
            phase = .listening
        case .userSpeaking:
            phase = .userSpeaking
        case .thinking:
            phase = .thinking
        case .toolWorking:
            phase = .toolWorking
        case .speaking:
            phase = .speaking
        case .reconnecting:
            phase = .reconnecting
        case .paused:
            phase = .paused
            isMuted = true
        case .failed:
            phase = .failed("AgentOps is temporarily unavailable.")
        case .answer:
            phase = .listening
            latestResult = Self.mockResult(kind: .answer)
        case .clarify:
            phase = .listening
            latestResult = Self.mockResult(kind: .clarify)
        case .durable:
            phase = .toolWorking
            latestResult = Self.mockResult(kind: .durableWork)
        case .offlineDraft:
            phase = .reconnecting
            transcriptEntries = [
                VoiceTranscriptEntry(
                    role: .system,
                    text: "Saved locally. This request will sync when AgentOps reconnects."
                ),
            ]
        case .realtimeUnavailable:
            phase = .failed(
                "AgentOps could not open the voice session. Your request was not sent."
            )
        case .gatewayUnavailable:
            phase = .reconnecting
            transcriptEntries = [
                VoiceTranscriptEntry(
                    role: .system,
                    text: "AgentOps is reconnecting. Any unsent request stays privately on this iPhone."
                ),
            ]
        case .claudeUnavailable:
            phase = .failed(
                "Claude Max is temporarily unavailable. AgentOps did not switch providers or create a task."
            )
        case .contextUnavailable:
            phase = .failed(
                "Required Wiki context is unavailable. AgentOps did not create durable work."
            )
        case .captureUnavailable:
            phase = .failed(
                "AgentOps could not capture durable work. The request is saved privately on this iPhone."
            )
            transcriptEntries = [
                VoiceTranscriptEntry(
                    role: .system,
                    text: "Saved locally with the same request identity for a safe retry."
                ),
            ]
        case .lockedWorkerUnavailable:
            phase = .failed(
                "The locked worker is unavailable. AgentOps did not fall back to another provider."
            )
        case .failedVerification:
            phase = .listening
        }
    }

    private static func mockResult(
        kind: AgentOpsTurnKind
    ) -> AgentOpsTurnResult {
        let routing = AgentOpsTurnRoutingIntent(
            mode: .auto,
            implementer: kind == .durableWork ? .claude : nil,
            reviewer: kind == .durableWork ? "ringer" : nil,
            allowFallback: true,
            fallbackRuntime: .codex,
            reason: "AgentOps selected the bounded execution path."
        )
        let source = AgentOpsSourceHandle(
            kind: kind == .durableWork ? "task" : "wiki",
            label: kind == .durableWork ? "AgentOps task" : "Team Wiki",
            url: URL(
                string: kind == .durableWork
                    ? "https://agentops.revopsglobal.com/fleet/tasks/e7e843c5-733d-4492-a863-1c337684653b"
                    : "https://agentops.revopsglobal.com/wiki"
            )!
        )

        switch kind {
        case .answer:
            return AgentOpsTurnResult(
                kind: .answer,
                speechText: "AgentOps found the answer in the Team Wiki.",
                displayText: "AgentOps found the current answer in the Team Wiki.",
                sources: [source],
                routingIntent: routing,
                approvalTier: .routineVoice,
                executionBrief: nil,
                task: nil,
                unavailableSources: []
            )
        case .clarify:
            return AgentOpsTurnResult(
                kind: .clarify,
                speechText: "Should this be a code change or an operating decision?",
                displayText: "Clarification needed: code change or operating decision?",
                sources: [source],
                routingIntent: routing,
                approvalTier: .routineVoice,
                executionBrief: nil,
                task: nil,
                unavailableSources: []
            )
        case .durableWork:
            return AgentOpsTurnResult(
                kind: .durableWork,
                speechText: "Captured in AgentOps and routed to Claude with Ringer review.",
                displayText: "Durable work captured and routed to Claude with Ringer review.",
                sources: [source],
                routingIntent: routing,
                approvalTier: .routineVoice,
                executionBrief: nil,
                task: AgentOpsTurnTaskSummary(
                    id: UUID(uuidString: "e7e843c5-733d-4492-a863-1c337684653b")!,
                    title: "Ship AgentOps native voice mode",
                    status: "in_progress"
                ),
                unavailableSources: []
            )
        }
    }
}
