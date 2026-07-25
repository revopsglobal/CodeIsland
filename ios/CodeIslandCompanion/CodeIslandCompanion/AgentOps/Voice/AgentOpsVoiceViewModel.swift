import AVFoundation
import Combine
import Foundation

struct AgentOpsVoiceRecording: Equatable, Sendable {
    let data: Data
    let contentType: String
}

@MainActor
protocol AgentOpsVoiceAudioHandling: AnyObject {
    func startRecording() async throws
    func stopRecording() throws -> AgentOpsVoiceRecording
    func play(_ audio: Data) async throws
    func cancel()
}

@MainActor
protocol AgentOpsVoiceServicing: AnyObject {
    func transcribe(_ recording: AgentOpsVoiceRecording) async throws -> String
    func executeTurn(transcript: String) async throws -> AgentOpsTurnExecution
    func synthesize(_ text: String) async throws -> Data
}

enum AgentOpsVoiceAudioError: LocalizedError {
    case microphonePermissionDenied
    case recordingFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required for AgentOps Voice."
        case .recordingFailed:
            return "The recording could not be captured."
        case .playbackFailed:
            return "The answer is shown, but its audio could not be played."
        }
    }
}

@MainActor
final class AgentOpsVoiceAudioController: NSObject,
    AgentOpsVoiceAudioHandling,
    AVAudioPlayerDelegate {
    private let audioSession: AVAudioSession
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var player: AVAudioPlayer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
    }

    func startRecording() async throws {
        cancel()
        let permitted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard permitted else {
            throw AgentOpsVoiceAudioError.microphonePermissionDenied
        }

        try audioSession.setCategory(
            .record,
            mode: .spokenAudio,
            options: []
        )
        try audioSession.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "agentops-voice-\(UUID().uuidString.lowercased())"
            )
            .appendingPathExtension("m4a")
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
        )
        recorder.isMeteringEnabled = false
        guard recorder.prepareToRecord(), recorder.record(forDuration: 60) else {
            try? audioSession.setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            throw AgentOpsVoiceAudioError.recordingFailed
        }
        self.recorder = recorder
        recordingURL = url
    }

    func stopRecording() throws -> AgentOpsVoiceRecording {
        guard let recorder, let recordingURL else {
            throw AgentOpsVoiceAudioError.recordingFailed
        }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        try? audioSession.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        defer { try? FileManager.default.removeItem(at: recordingURL) }
        let data = try Data(contentsOf: recordingURL)
        guard !data.isEmpty else {
            throw AgentOpsVoiceAudioError.recordingFailed
        }
        return AgentOpsVoiceRecording(
            data: data,
            contentType: "audio/m4a"
        )
    }

    func play(_ audio: Data) async throws {
        guard !audio.isEmpty else {
            throw AgentOpsVoiceAudioError.playbackFailed
        }
        finishPlayback(error: CancellationError())
        try await withCheckedThrowingContinuation { continuation in
            playbackContinuation = continuation
            do {
                try audioSession.setCategory(
                    .playback,
                    mode: .spokenAudio,
                    options: [.duckOthers]
                )
                try audioSession.setActive(true)
                let player = try AVAudioPlayer(
                    data: audio,
                    fileTypeHint: AVFileType.mp3.rawValue
                )
                player.delegate = self
                player.volume = 1
                self.player = player
                guard player.prepareToPlay(), player.play() else {
                    throw AgentOpsVoiceAudioError.playbackFailed
                }
            } catch {
                finishPlayback(error: error)
            }
        }
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        finishPlayback(error: CancellationError())
        try? audioSession.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        finishPlayback(
            error: flag ? nil : AgentOpsVoiceAudioError.playbackFailed
        )
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        finishPlayback(error: error ?? AgentOpsVoiceAudioError.playbackFailed)
    }

    private func finishPlayback(error: Error?) {
        player?.stop()
        player = nil
        try? audioSession.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        guard let continuation = playbackContinuation else { return }
        playbackContinuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

@MainActor
final class LiveAgentOpsVoiceService: AgentOpsVoiceServicing {
    private struct TurnArguments: Encodable {
        let transcript: String
    }

    private let client: AgentOpsClient
    private let turnTool: AgentOpsTurnTool

    init(client: AgentOpsClient, turnTool: AgentOpsTurnTool) {
        self.client = client
        self.turnTool = turnTool
    }

    func transcribe(
        _ recording: AgentOpsVoiceRecording
    ) async throws -> String {
        try await client.transcribeVoice(
            recording.data,
            contentType: recording.contentType
        )
    }

    func executeTurn(
        transcript: String
    ) async throws -> AgentOpsTurnExecution {
        let arguments = try JSONEncoder().encode(
            TurnArguments(transcript: transcript)
        )
        guard let json = String(data: arguments, encoding: .utf8) else {
            throw AgentOpsTurnToolError.invalidArguments
        }
        return try await turnTool.execute(
            callId: "chained-\(UUID().uuidString.lowercased())",
            argumentsJSON: json
        )
    }

    func synthesize(_ text: String) async throws -> Data {
        try await client.synthesizeVoice(text)
    }
}

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
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false

    let mockScenario: AgentOpsVoiceMockScenario?

    private let audioController: any AgentOpsVoiceAudioHandling
    private var service: (any AgentOpsVoiceServicing)?
    private weak var rootStore: AgentOpsRootStore?
    private let sessionID = UUID()
    private var activeTurn: Task<Void, Never>?

    init(
        mockScenario: AgentOpsVoiceMockScenario? = nil,
        audioController: (any AgentOpsVoiceAudioHandling)? = nil,
        service: (any AgentOpsVoiceServicing)? = nil
    ) {
        self.mockScenario = mockScenario
        self.audioController = audioController ?? AgentOpsVoiceAudioController()
        self.service = service
        if let mockScenario {
            applyMock(mockScenario)
        }
    }

    var isMock: Bool { mockScenario != nil }

    var stateTitle: String {
        switch phase {
        case .idle: return "Ready"
        case .connecting: return "Preparing microphone"
        case .listening: return "Recording"
        case .userSpeaking: return "Recording"
        case .thinking: return "Transcribing"
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
            return "Opening the microphone for one private turn."
        case .listening:
            return "Ask about the Wiki, work, repos, or create a task. Tap Stop & send when finished."
        case .userSpeaking:
            return "Your request is being recorded. Tap Stop & send when finished."
        case .thinking:
            return "OpenAI is turning your completed recording into text."
        case .toolWorking:
            return "AgentOps and Claude Max are loading context and choosing the right response path."
        case .speaking:
            return "The microphone is off while the AgentOps answer plays."
        case .reconnecting:
            return "Restoring the private AgentOps connection."
        case .paused:
            return "This voice turn is paused."
        case .failed(let message):
            return message
        }
    }

    var canStop: Bool {
        if isRecording { return true }
        switch phase {
        case .connecting, .thinking, .toolWorking, .speaking:
            return true
        default:
            return false
        }
    }

    var canStart: Bool {
        guard !isRecording, activeTurn == nil else { return false }
        switch phase {
        case .idle, .failed:
            return true
        default:
            return false
        }
    }

    func configure(rootStore: AgentOpsRootStore) {
        self.rootStore = rootStore
        guard !isMock, service == nil, let client = rootStore.client else {
            return
        }

        let tool = AgentOpsTurnTool(
            client: client,
            sessionID: sessionID,
            clientMetadata: .current(),
            draftStore: rootStore.draftStore
        )
        service = LiveAgentOpsVoiceService(
            client: client,
            turnTool: tool
        )
    }

    func startVoice() async {
        guard !isMock else {
            isRunning = true
            isRecording = true
            phase = .listening
            return
        }
        guard service != nil else {
            phase = .failed("AgentOps voice is not configured in this build.")
            return
        }
        guard canStart else { return }
        isRunning = true
        phase = .connecting
        do {
            try await audioController.startRecording()
            isRecording = true
            phase = .listening
        } catch {
            isRunning = false
            isRecording = false
            phase = .failed(
                error.localizedDescription.isEmpty
                    ? "The microphone could not start."
                    : error.localizedDescription
            )
        }
    }

    func finishRecording() {
        guard !isMock else {
            isRecording = false
            isRunning = false
            phase = .idle
            return
        }
        guard isRecording, activeTurn == nil else { return }

        let recording: AgentOpsVoiceRecording
        do {
            recording = try audioController.stopRecording()
        } catch {
            audioController.cancel()
            isRecording = false
            isRunning = false
            phase = .failed("The recording could not be captured. Try again.")
            return
        }
        isRecording = false
        phase = .thinking
        activeTurn = Task { @MainActor [weak self] in
            await self?.runTurn(recording)
        }
    }

    func endVoice() async {
        activeTurn?.cancel()
        activeTurn = nil
        audioController.cancel()
        isRecording = false
        isRunning = false
        phase = .idle
    }

    func stopResponse() {
        activeTurn?.cancel()
        activeTurn = nil
        audioController.cancel()
        isRecording = false
        isRunning = false
        phase = .idle
    }

    private func runTurn(_ recording: AgentOpsVoiceRecording) async {
        guard let service else {
            activeTurn = nil
            isRunning = false
            phase = .failed("AgentOps voice is not configured in this build.")
            return
        }

        do {
            let transcript = try await service.transcribe(recording)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard !transcript.isEmpty else {
                throw AgentOpsClientError.invalidResponse
            }
            transcriptEntries.append(
                VoiceTranscriptEntry(role: .user, text: transcript)
            )

            phase = .toolWorking
            let execution = try await service.executeTurn(
                transcript: transcript
            )
            try Task.checkCancellation()
            latestResult = execution.result
            rootStore?.recordTurnResult(execution.result)
            transcriptEntries.append(
                VoiceTranscriptEntry(
                    role: .assistant,
                    text: execution.result.speechText
                )
            )

            phase = .speaking
            let speech = try await service.synthesize(
                execution.result.speechText
            )
            try Task.checkCancellation()
            try await audioController.play(speech)
            try Task.checkCancellation()
            phase = .idle
            isRunning = false
        } catch is CancellationError {
            phase = .idle
            isRunning = false
        } catch {
            let failedPhase = phase
            isRunning = false
            switch failedPhase {
            case .thinking:
                phase = .failed(
                    "I couldn’t transcribe that recording. Tap Start voice to try again."
                )
            case .toolWorking:
                if rootStore?.draftStore?.drafts.isEmpty == false {
                    transcriptEntries.append(
                        VoiceTranscriptEntry(
                            role: .system,
                            text: "Saved privately on this iPhone. It will retry with the same request identity when AgentOps reconnects."
                        )
                    )
                }
                phase = .failed(
                    "AgentOps could not complete this turn. Your words will not be sent again automatically by the microphone."
                )
            case .speaking:
                phase = .failed(
                    "The AgentOps answer is shown, but its audio could not be played."
                )
            default:
                phase = .failed("AgentOps voice could not complete this turn.")
            }
        }
        activeTurn = nil
    }

    private func applyMock(_ scenario: AgentOpsVoiceMockScenario) {
        isRunning = true
        switch scenario {
        case .listening:
            phase = .listening
            isRecording = true
        case .userSpeaking:
            phase = .userSpeaking
            isRecording = true
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
        case .failed:
            phase = .failed("AgentOps is temporarily unavailable.")
        case .answer:
            phase = .idle
            latestResult = Self.mockResult(kind: .answer)
        case .clarify:
            phase = .idle
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
            phase = .idle
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
