import Foundation

struct RealtimeCredential: Equatable, Sendable {
    let sessionId: String
    let clientSecret: String
    let model: String
    let connectDeadline: Date
}

enum RealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

struct RealtimeToolDefinition: Equatable, @unchecked Sendable {
    let name: String
    let description: String
    let parametersJSON: [String: Any]

    static func == (
        lhs: RealtimeToolDefinition,
        rhs: RealtimeToolDefinition
    ) -> Bool {
        lhs.name == rhs.name
            && lhs.description == rhs.description
            && NSDictionary(dictionary: lhs.parametersJSON)
                .isEqual(to: rhs.parametersJSON)
    }
}

enum AgentOpsRealtimeProtocol {
    static let toolDefinitions = [AgentOpsTurnTool.definition]

    static let instructions = """
    You are the speech layer for AgentOps Voice. For every semantic user turn, call \
    agentops_turn exactly once with the user's complete current request. Do not \
    independently answer operational, contextual, repository, Wiki, task-state, or \
    execution questions. Do not claim work was captured, started, completed, verified, \
    or approved unless the agentops_turn result says so. After the tool returns, speak \
    only its speech_text faithfully and use display_text and sources for the on-screen \
    response. If kind is clarify, ask the returned clarification. If kind is \
    durable_work, include the canonical AgentOps task UUID returned by the tool. Voice \
    can never approve an action; approvals require the app's explicit on-screen button.
    """
}

enum RealtimeServerEvent: Equatable, Sendable {
    case sessionCreated(sessionId: String)
    case sessionUpdated
    case inputAudioBufferSpeechStarted
    case inputAudioBufferSpeechStopped
    case responseCreated(responseId: String)
    case functionCallArgumentsDone(
        callId: String,
        name: String,
        argumentsJSON: String
    )
    case responseAudioTranscriptDelta(text: String)
    case responseDone
    case error(message: String)
    case unknown(type: String)

    static func decode(from data: Data) -> RealtimeServerEvent? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let type = object["type"] as? String
        else {
            return nil
        }

        switch type {
        case "session.created":
            let session = object["session"] as? [String: Any]
            return .sessionCreated(sessionId: session?["id"] as? String ?? "")
        case "session.updated":
            return .sessionUpdated
        case "input_audio_buffer.speech_started":
            return .inputAudioBufferSpeechStarted
        case "input_audio_buffer.speech_stopped":
            return .inputAudioBufferSpeechStopped
        case "response.created":
            let response = object["response"] as? [String: Any]
            return .responseCreated(
                responseId: response?["id"] as? String ?? ""
            )
        case "response.function_call_arguments.done":
            return .functionCallArgumentsDone(
                callId: object["call_id"] as? String ?? "",
                name: object["name"] as? String ?? "",
                argumentsJSON: object["arguments"] as? String ?? "{}"
            )
        case "response.audio_transcript.delta":
            return .responseAudioTranscriptDelta(
                text: object["delta"] as? String ?? ""
            )
        case "response.done":
            return .responseDone
        case "error":
            let error = object["error"] as? [String: Any]
            return .error(
                message: error?["message"] as? String
                    ?? "Unknown Realtime error"
            )
        default:
            return .unknown(type: type)
        }
    }
}

enum RealtimeClientEvent: Equatable, @unchecked Sendable {
    case sessionUpdate(
        instructions: String,
        tools: [RealtimeToolDefinition],
        voice: String?
    )
    case functionCallOutput(callId: String, outputJSON: String)
    case responseCreate
    case responseCancel(responseId: String)
    case outputAudioBufferClear

    func toJSONObject() -> [String: Any] {
        switch self {
        case .sessionUpdate(let instructions, let tools, let voice):
            var audio: [String: Any] = [
                "input": [
                    "turn_detection": [
                        "type": "server_vad",
                        "threshold": NSDecimalNumber(string: "0.7"),
                        "prefix_padding_ms": 300,
                        "silence_duration_ms": 700,
                        "create_response": true,
                        "interrupt_response": true,
                    ] as [String: Any],
                ] as [String: Any],
            ]
            if let voice {
                audio["output"] = ["voice": voice]
            }
            return [
                "type": "session.update",
                "session": [
                    "type": "realtime",
                    "instructions": instructions,
                    "audio": audio,
                    "tools": tools.map { tool in
                        [
                            "type": "function",
                            "name": tool.name,
                            "description": tool.description,
                            "parameters": tool.parametersJSON,
                        ] as [String: Any]
                    },
                ] as [String: Any],
            ]
        case .functionCallOutput(let callId, let outputJSON):
            return [
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": outputJSON,
                ],
            ]
        case .responseCreate:
            return ["type": "response.create"]
        case .responseCancel(let responseId):
            return [
                "type": "response.cancel",
                "response_id": responseId,
            ]
        case .outputAudioBufferClear:
            return ["type": "output_audio_buffer.clear"]
        }
    }

    func toData() throws -> Data {
        try JSONSerialization.data(withJSONObject: toJSONObject())
    }

    static func == (
        lhs: RealtimeClientEvent,
        rhs: RealtimeClientEvent
    ) -> Bool {
        NSDictionary(dictionary: lhs.toJSONObject())
            .isEqual(to: rhs.toJSONObject())
    }
}
