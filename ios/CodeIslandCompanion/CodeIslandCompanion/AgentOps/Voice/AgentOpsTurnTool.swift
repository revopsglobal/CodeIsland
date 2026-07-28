import Foundation

enum AgentOpsTurnKind: String, Codable, Sendable {
    case answer
    case clarify
    case durableWork = "durable_work"
}

enum AgentOpsApprovalTier: String, Codable, Sendable {
    case routineVoice = "routine_voice"
    case explicitTap = "explicit_tap"
}

struct AgentOpsConversationTurn: Codable, Equatable, Sendable {
    let role: String
    let text: String
}

struct AgentOpsClientMetadata: Codable, Equatable, Sendable {
    let platform: String
    let appVersion: String
    let build: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case platform
        case appVersion = "app_version"
        case build
        case locale
    }

    static func current(bundle: Bundle = .main) -> AgentOpsClientMetadata {
        AgentOpsClientMetadata(
            platform: "ios",
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            build: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            locale: Locale.current.identifier
        )
    }
}

struct AgentOpsTurnRequest: Codable, Equatable, Sendable {
    let sessionID: UUID
    let turnID: UUID
    let idempotencyKey: UUID
    let transcript: String
    let conversation: [AgentOpsConversationTurn]
    let client: AgentOpsClientMetadata

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case idempotencyKey = "idempotency_key"
        case transcript
        case conversation
        case client
    }
}

struct AgentOpsTurnRoutingIntent: Codable, Equatable, Sendable {
    let mode: AgentOpsRoutingMode
    let implementer: AgentOpsWorkerRuntime?
    let reviewer: String?
    let allowFallback: Bool
    let fallbackRuntime: AgentOpsWorkerRuntime?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case mode
        case implementer
        case reviewer
        case allowFallback = "allow_fallback"
        case fallbackRuntime = "fallback_runtime"
        case reason
    }
}

struct AgentOpsExecutionBrief: Codable, Equatable, Sendable {
    let title: String
    let description: String
    let priority: String
    let authorityClass: String
    let riskClass: String
    let reviewPolicy: String
    let successCriteria: [String]
    let outOfScope: [String]
    let escalationTriggers: [String]
    let sourceHierarchy: [String]
    let preferredRuntime: AgentOpsWorkerRuntime
    let requiredCapabilities: [String]
    let requiredProofKinds: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case priority
        case authorityClass = "authority_class"
        case riskClass = "risk_class"
        case reviewPolicy = "review_policy"
        case successCriteria = "success_criteria"
        case outOfScope = "out_of_scope"
        case escalationTriggers = "escalation_triggers"
        case sourceHierarchy = "source_hierarchy"
        case preferredRuntime = "preferred_runtime"
        case requiredCapabilities = "required_capabilities"
        case requiredProofKinds = "required_proof_kinds"
    }
}

struct AgentOpsTurnTaskSummary: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let status: String
}

struct AgentOpsTurnResult: Codable, Equatable, Sendable {
    let kind: AgentOpsTurnKind
    let speechText: String
    let displayText: String
    let sources: [AgentOpsSourceHandle]
    let routingIntent: AgentOpsTurnRoutingIntent
    let approvalTier: AgentOpsApprovalTier
    let executionBrief: AgentOpsExecutionBrief?
    let task: AgentOpsTurnTaskSummary?
    let unavailableSources: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case speechText = "speech_text"
        case displayText = "display_text"
        case sources
        case routingIntent = "routing_intent"
        case approvalTier = "approval_tier"
        case executionBrief = "execution_brief"
        case task
        case unavailableSources = "unavailable_sources"
    }
}

struct AgentOpsTurnExecution: Equatable, Sendable {
    let request: AgentOpsTurnRequest
    let result: AgentOpsTurnResult
    let outputJSON: String
}

enum AgentOpsTurnToolError: Error, Equatable {
    case invalidArguments
    case invalidResult
}

struct AgentOpsTurnTool {
    static let definition = RealtimeToolDefinition(
        name: "agentops_turn",
        description: """
        Send the user's complete semantic turn to AgentOps. AgentOps owns Wiki \
        context, task capture, routing, approvals, proof, and the response.
        """,
        parametersJSON: [
            "type": "object",
            "properties": [
                "transcript": [
                    "type": "string",
                    "description": "The user's complete current request.",
                ],
            ],
            "required": ["transcript"],
            "additionalProperties": false,
        ]
    )

    private struct Arguments: Decodable {
        let transcript: String
    }

    private let client: AgentOpsClient
    private let sessionID: UUID
    private let clientMetadata: AgentOpsClientMetadata
    private let uuid: () -> UUID
    private let draftStore: VoiceTurnDraftStore?
    private let receiptJournal: AgentOpsMobileReceiptJournal

    @MainActor
    init(
        client: AgentOpsClient,
        sessionID: UUID,
        clientMetadata: AgentOpsClientMetadata,
        draftStore: VoiceTurnDraftStore? = nil,
        receiptJournal: AgentOpsMobileReceiptJournal? = nil,
        uuid: @escaping () -> UUID = UUID.init
    ) {
        self.client = client
        self.sessionID = sessionID
        self.clientMetadata = clientMetadata
        self.draftStore = draftStore
        self.receiptJournal = receiptJournal ?? .shared
        self.uuid = uuid
    }

    @MainActor
    func execute(
        callId: String,
        argumentsJSON: String
    ) async throws -> AgentOpsTurnExecution {
        guard
            let data = argumentsJSON.data(using: .utf8),
            let arguments = try? JSONDecoder().decode(
                Arguments.self,
                from: data
            )
        else {
            throw AgentOpsTurnToolError.invalidArguments
        }
        let transcript = arguments.transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty, transcript.count <= 8_000 else {
            throw AgentOpsTurnToolError.invalidArguments
        }

        let turnID = uuid()
        let request = AgentOpsTurnRequest(
            sessionID: sessionID,
            turnID: turnID,
            idempotencyKey: turnID,
            transcript: transcript,
            conversation: [],
            client: clientMetadata
        )
        let draft = try draftStore?.save(request)
        if let draft {
            receiptJournal.record(
                .draftSaved,
                sessionID: sessionID,
                draftCount: draftStore?.drafts.count
            )
            try draftStore?.markAttempted(draftID: draft.id)
        }
        let result = try await client.performTurn(request)
        guard
            !result.speechText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw AgentOpsTurnToolError.invalidResult
        }
        if let draft {
            try draftStore?.finish(draftID: draft.id, result: result)
            receiptJournal.record(
                .draftCompleted,
                sessionID: sessionID,
                taskID: result.task?.id,
                draftCount: draftStore?.drafts.count
            )
        }
        let encoded = try JSONEncoder.agentOps.encode(result)
        guard let output = String(data: encoded, encoding: .utf8) else {
            throw AgentOpsTurnToolError.invalidResult
        }
        return AgentOpsTurnExecution(
            request: request,
            result: result,
            outputJSON: output
        )
    }

    @MainActor
    func replay(_ draft: VoiceTurnDraft) async throws -> AgentOpsTurnExecution {
        guard
            let persisted = draftStore?.replayRequest(for: draft.id),
            persisted == draft.request
        else {
            throw AgentOpsTurnToolError.invalidArguments
        }
        try draftStore?.markAttempted(draftID: draft.id)
        receiptJournal.record(
            .draftReplayed,
            sessionID: sessionID,
            draftCount: draftStore?.drafts.count
        )
        let result = try await client.performTurn(persisted)
        guard
            !result.speechText.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw AgentOpsTurnToolError.invalidResult
        }
        try draftStore?.finish(draftID: draft.id, result: result)
        receiptJournal.record(
            .draftCompleted,
            sessionID: sessionID,
            taskID: result.task?.id,
            draftCount: draftStore?.drafts.count
        )
        let encoded = try JSONEncoder.agentOps.encode(result)
        guard let output = String(data: encoded, encoding: .utf8) else {
            throw AgentOpsTurnToolError.invalidResult
        }
        return AgentOpsTurnExecution(
            request: persisted,
            result: result,
            outputJSON: output
        )
    }
}

extension JSONEncoder {
    static var agentOps: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var agentOps: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
