import Foundation

enum VoiceSessionPhase: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case userSpeaking
    case thinking
    case toolWorking
    case speaking
    case reconnecting
    case paused
    case failed(String)
}

enum VoiceSessionMode: Equatable, Sendable {
    case active
    case paused
}

struct PendingVoiceToolCall: Equatable, Identifiable, Sendable {
    var id: String { callId }
    let callId: String
    let argumentsJSON: String
}

struct VoiceSessionState: Equatable, Sendable {
    var phase: VoiceSessionPhase = .idle
    var mode: VoiceSessionMode = .active
    var activeResponseId: String?
    var isCallEstablished = false
    var pendingCalls: [PendingVoiceToolCall] = []
    var lastAssistantTranscript = ""
    var hasDeferredResponse = false
    var reconnectAttempt = 0
    var lastError: String?

    private(set) var seenCallIds: [String] = []
    private static let maximumRememberedCallIds = 200

    mutating func rememberCallIfNew(_ callId: String) -> Bool {
        guard !callId.isEmpty, !seenCallIds.contains(callId) else {
            return false
        }
        seenCallIds.append(callId)
        if seenCallIds.count > Self.maximumRememberedCallIds {
            seenCallIds.removeFirst(
                seenCallIds.count - Self.maximumRememberedCallIds
            )
        }
        return true
    }
}

enum VoiceSessionEffect: Equatable, Sendable {
    case send(RealtimeClientEvent)
    case setMicrophoneEnabled(Bool)
    case executeTurn(callId: String, argumentsJSON: String)
    case scheduleReconnect(after: TimeInterval)
    case log(String)
}

enum VoiceSessionEvent: Equatable, Sendable {
    case server(RealtimeServerEvent)
    case callEstablished
    case callEstablishmentFailed(String)
    case transportDisconnected(reason: String?)
    case toolResultReady(callId: String, outputJSON: String)
    case toolExecutionFailed(callId: String, message: String)
    case stopRequested
    case pauseRequested
    case resumeRequested
}

enum VoiceSessionReducer {
    static func reduce(
        _ state: inout VoiceSessionState,
        _ event: VoiceSessionEvent
    ) -> [VoiceSessionEffect] {
        switch event {
        case .server(let serverEvent):
            return reduceServer(&state, serverEvent)

        case .callEstablished:
            state.isCallEstablished = true
            state.reconnectAttempt = 0
            state.lastError = nil
            state.phase = state.mode == .paused ? .paused : .listening
            return []

        case .callEstablishmentFailed(let message):
            state.isCallEstablished = false
            state.phase = .failed(message)
            state.lastError = message
            return [.log("Realtime call establishment failed: \(message)")]

        case .transportDisconnected(let reason):
            state.isCallEstablished = false
            state.phase = .reconnecting
            let delay = backoffDelay(attempt: state.reconnectAttempt)
            state.reconnectAttempt += 1
            var effects: [VoiceSessionEffect] = [
                .scheduleReconnect(after: delay),
            ]
            if let reason {
                effects.append(.log("Realtime disconnected: \(reason)"))
            }
            return effects

        case .toolResultReady(let callId, let outputJSON):
            state.pendingCalls.removeAll { $0.callId == callId }
            var effects: [VoiceSessionEffect] = [
                .send(.functionCallOutput(
                    callId: callId,
                    outputJSON: outputJSON
                )),
            ]
            if state.mode == .active {
                effects.append(.send(.responseCreate))
                state.phase = .thinking
            } else {
                state.hasDeferredResponse = true
                state.phase = .paused
            }
            return effects

        case .toolExecutionFailed(let callId, let message):
            state.pendingCalls.removeAll { $0.callId == callId }
            let output = errorOutput(message)
            var effects: [VoiceSessionEffect] = [
                .send(.functionCallOutput(
                    callId: callId,
                    outputJSON: output
                )),
                .log("agentops_turn failed: \(message)"),
            ]
            if state.mode == .active {
                effects.insert(.send(.responseCreate), at: 1)
            } else {
                state.hasDeferredResponse = true
                state.phase = .paused
            }
            return effects

        case .stopRequested:
            guard
                state.isCallEstablished,
                let responseId = state.activeResponseId
            else {
                return []
            }
            state.activeResponseId = nil
            state.lastAssistantTranscript = ""
            state.phase = state.mode == .paused ? .paused : .listening
            return [
                .send(.responseCancel(responseId: responseId)),
                .send(.outputAudioBufferClear),
            ]

        case .pauseRequested:
            guard state.mode == .active else { return [] }
            state.mode = .paused
            state.phase = .paused
            var effects: [VoiceSessionEffect] = [
                .setMicrophoneEnabled(false),
            ]
            if let responseId = state.activeResponseId {
                effects.append(
                    .send(.responseCancel(responseId: responseId))
                )
                effects.append(.send(.outputAudioBufferClear))
            }
            state.activeResponseId = nil
            state.lastAssistantTranscript = ""
            return effects

        case .resumeRequested:
            guard state.mode == .paused else { return [] }
            state.mode = .active
            state.phase = state.isCallEstablished ? .listening : .reconnecting
            var effects: [VoiceSessionEffect] = [
                .setMicrophoneEnabled(true),
            ]
            if state.isCallEstablished, state.hasDeferredResponse {
                state.hasDeferredResponse = false
                effects.append(.send(.responseCreate))
                state.phase = .thinking
            }
            return effects
        }
    }

    private static func reduceServer(
        _ state: inout VoiceSessionState,
        _ event: RealtimeServerEvent
    ) -> [VoiceSessionEffect] {
        switch event {
        case .sessionCreated, .sessionUpdated:
            return []

        case .inputAudioBufferSpeechStarted:
            guard state.mode == .active else { return [] }
            state.phase = .userSpeaking
            guard let responseId = state.activeResponseId else { return [] }
            state.activeResponseId = nil
            state.lastAssistantTranscript = ""
            return [
                .send(.responseCancel(responseId: responseId)),
                .send(.outputAudioBufferClear),
            ]

        case .inputAudioBufferSpeechStopped:
            guard state.mode == .active else { return [] }
            state.phase = .thinking
            return []

        case .responseCreated(let responseId):
            state.activeResponseId = responseId
            state.phase = state.mode == .paused ? .paused : .thinking
            return []

        case .functionCallArgumentsDone(
            let callId,
            let name,
            let argumentsJSON
        ):
            guard state.rememberCallIfNew(callId) else {
                return [.log("Ignoring duplicate Realtime call_id \(callId)")]
            }
            guard name == AgentOpsTurnTool.definition.name else {
                let output = errorOutput("unsupported tool")
                return [
                    .send(.functionCallOutput(
                        callId: callId,
                        outputJSON: output
                    )),
                    .send(.responseCreate),
                    .log("Rejected unexpected Realtime tool \(name)"),
                ]
            }
            state.pendingCalls.append(
                PendingVoiceToolCall(
                    callId: callId,
                    argumentsJSON: argumentsJSON
                )
            )
            state.phase = .toolWorking
            return [
                .executeTurn(
                    callId: callId,
                    argumentsJSON: argumentsJSON
                ),
            ]

        case .responseAudioTranscriptDelta(let text):
            guard state.mode == .active else { return [] }
            state.phase = .speaking
            state.lastAssistantTranscript += text
            return []

        case .responseDone:
            state.activeResponseId = nil
            state.lastAssistantTranscript = ""
            if state.mode == .paused {
                state.phase = .paused
            } else {
                state.phase = state.pendingCalls.isEmpty
                    ? .listening
                    : .toolWorking
            }
            return []

        case .error(let message):
            state.phase = .failed(message)
            state.lastError = message
            return [.log("Realtime error: \(message)")]

        case .unknown:
            return []
        }
    }

    static func backoffDelay(attempt: Int) -> TimeInterval {
        min(30, pow(2, Double(max(0, attempt))))
    }

    private static func errorOutput(_ message: String) -> String {
        struct Payload: Encodable {
            let error: String
        }
        let data = (try? JSONEncoder().encode(Payload(error: message)))
            ?? Data(#"{"error":"unknown"}"#.utf8)
        return String(data: data, encoding: .utf8)
            ?? #"{"error":"unknown"}"#
    }
}
