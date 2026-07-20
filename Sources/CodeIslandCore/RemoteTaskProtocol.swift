import CryptoKit
import Foundation

public enum RemoteTaskProvider: String, Codable, CaseIterable, Equatable, Sendable {
    case auto
    case codex
    case claude
}

public enum RemoteTaskAuthority: String, Codable, CaseIterable, Equatable, Sendable {
    case editAndTest = "edit-and-test"
}

/// Opaque, wire-safe workspace metadata. Absolute Mac paths never leave the
/// host; Buddy submits only this identifier after the user picks the name.
public struct RemoteWorkspaceSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct RemoteWorkspaceSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let workspaces: [RemoteWorkspaceSummary]

    public init(version: Int = Self.currentVersion, workspaces: [RemoteWorkspaceSummary]) {
        self.version = version
        self.workspaces = workspaces
    }
}

public enum RemoteTaskState: String, Codable, CaseIterable, Equatable, Sendable {
    case waitingForMac = "waiting-for-mac"
    case queued
    case working
    case needsYou = "needs-you"
    case verified
    case failed
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .verified, .failed, .cancelled:
            return true
        case .waitingForMac, .queued, .working, .needsYou:
            return false
        }
    }
}

/// Metadata for an attachment that Buddy will upload through the authenticated
/// task API. The descriptor intentionally has no local path or download URL.
public struct RemoteTaskAttachmentDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let byteCount: Int64
    public let mediaType: String
    public let sha256: String

    public init(
        id: String,
        displayName: String,
        byteCount: Int64,
        mediaType: String,
        sha256: String
    ) {
        self.id = id
        self.displayName = displayName
        self.byteCount = byteCount
        self.mediaType = mediaType
        self.sha256 = sha256
    }
}

public struct RemoteTaskCreateRequest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let clientTaskID: UUID
    public let idempotencyKey: UUID
    public let prompt: String
    public let workspaceID: String?
    public let provider: RemoteTaskProvider
    public let authority: RemoteTaskAuthority
    public let attachments: [RemoteTaskAttachmentDescriptor]
    public let requestedProof: String?
    public let createdAt: Date

    public init(
        version: Int = Self.currentVersion,
        clientTaskID: UUID,
        idempotencyKey: UUID,
        prompt: String,
        workspaceID: String?,
        provider: RemoteTaskProvider,
        authority: RemoteTaskAuthority,
        attachments: [RemoteTaskAttachmentDescriptor] = [],
        requestedProof: String? = nil,
        createdAt: Date = Date()
    ) {
        self.version = version
        self.clientTaskID = clientTaskID
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.workspaceID = workspaceID
        self.provider = provider
        self.authority = authority
        self.attachments = attachments
        self.requestedProof = requestedProof
        self.createdAt = createdAt
    }
}

public enum RemoteTaskSourceState: String, Codable, CaseIterable, Equatable, Sendable {
    case unchanged
    case edited
    case committed
    case pushed
    case merged
    case deployed
}

public enum RemoteTaskFileChangeKind: String, Codable, CaseIterable, Equatable, Sendable {
    case added
    case modified
    case deleted
    case renamed
}

public struct RemoteTaskChangedFile: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public let kind: RemoteTaskFileChangeKind
    public let previousPath: String?

    public var id: String { "\(kind.rawValue):\(path)" }

    public init(path: String, kind: RemoteTaskFileChangeKind, previousPath: String? = nil) {
        self.path = path
        self.kind = kind
        self.previousPath = previousPath
    }
}

public struct RemoteTaskCheck: Codable, Equatable, Sendable {
    public let command: String
    public let exitCode: Int
    public let summary: String
    public let durationSeconds: TimeInterval?

    public init(
        command: String,
        exitCode: Int,
        summary: String,
        durationSeconds: TimeInterval? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.summary = summary
        self.durationSeconds = durationSeconds
    }
}

public struct RemoteTaskEvidence: Codable, Equatable, Sendable {
    public let branch: String?
    public let changedFiles: [RemoteTaskChangedFile]
    public let checks: [RemoteTaskCheck]
    public let warnings: [String]
    public let sourceState: RemoteTaskSourceState

    public init(
        branch: String? = nil,
        changedFiles: [RemoteTaskChangedFile] = [],
        checks: [RemoteTaskCheck] = [],
        warnings: [String] = [],
        sourceState: RemoteTaskSourceState = .unchanged
    ) {
        self.branch = branch
        self.changedFiles = changedFiles
        self.checks = checks
        self.warnings = warnings
        self.sourceState = sourceState
    }
}

public enum RemoteTaskReceiptKind: String, Codable, CaseIterable, Equatable, Sendable {
    case accepted
    case started
    case changed
    case tested
    case needsApproval = "needs-approval"
    case needsAnswer = "needs-answer"
    case finished
    case failed
    case cancelled
}

public struct RemoteTaskReceipt: Codable, Equatable, Identifiable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let eventID: UUID
    public let taskID: UUID
    public let sequence: UInt64
    public let kind: RemoteTaskReceiptKind
    public let state: RemoteTaskState
    public let summary: String
    public let observedAt: Date
    public let provider: RemoteTaskProvider?
    public let providerSessionID: String?
    public let evidence: RemoteTaskEvidence?

    public var id: UUID { eventID }

    public init(
        version: Int = Self.currentVersion,
        eventID: UUID = UUID(),
        taskID: UUID,
        sequence: UInt64,
        kind: RemoteTaskReceiptKind,
        state: RemoteTaskState,
        summary: String,
        observedAt: Date = Date(),
        provider: RemoteTaskProvider? = nil,
        providerSessionID: String? = nil,
        evidence: RemoteTaskEvidence? = nil
    ) {
        self.version = version
        self.eventID = eventID
        self.taskID = taskID
        self.sequence = sequence
        self.kind = kind
        self.state = state
        self.summary = summary
        self.observedAt = observedAt
        self.provider = provider
        self.providerSessionID = providerSessionID
        self.evidence = evidence
    }
}

public struct RemoteTaskSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let clientTaskID: UUID
    public let idempotencyKey: UUID
    public let title: String
    public let workspaceID: String
    public let workspaceName: String
    public let provider: RemoteTaskProvider
    public let authority: RemoteTaskAuthority
    public let state: RemoteTaskState
    public let createdAt: Date
    public let updatedAt: Date
    public let lastReceiptSequence: UInt64
    public let latestSummary: String?
    public let providerSessionID: String?
    public let evidence: RemoteTaskEvidence?

    public init(
        id: UUID,
        clientTaskID: UUID,
        idempotencyKey: UUID,
        title: String,
        workspaceID: String,
        workspaceName: String,
        provider: RemoteTaskProvider,
        authority: RemoteTaskAuthority,
        state: RemoteTaskState,
        createdAt: Date,
        updatedAt: Date,
        lastReceiptSequence: UInt64,
        latestSummary: String? = nil,
        providerSessionID: String? = nil,
        evidence: RemoteTaskEvidence? = nil
    ) {
        self.id = id
        self.clientTaskID = clientTaskID
        self.idempotencyKey = idempotencyKey
        self.title = title
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.provider = provider
        self.authority = authority
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastReceiptSequence = lastReceiptSequence
        self.latestSummary = latestSummary
        self.providerSessionID = providerSessionID
        self.evidence = evidence
    }

    /// Returns a new summary only when the host receipt advances the task's
    /// monotonic sequence. Delayed network delivery can therefore never
    /// regress Buddy to an older state.
    public func applying(_ receipt: RemoteTaskReceipt) -> RemoteTaskSummary {
        guard receipt.taskID == id, receipt.sequence > lastReceiptSequence else { return self }
        return RemoteTaskSummary(
            id: id,
            clientTaskID: clientTaskID,
            idempotencyKey: idempotencyKey,
            title: title,
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            provider: receipt.provider ?? provider,
            authority: authority,
            state: receipt.state,
            createdAt: createdAt,
            updatedAt: receipt.observedAt,
            lastReceiptSequence: receipt.sequence,
            latestSummary: receipt.summary,
            providerSessionID: receipt.providerSessionID ?? providerSessionID,
            evidence: receipt.evidence ?? evidence
        )
    }
}

public struct RemoteTaskSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let serverName: String
    public let generatedAt: Date
    public let tasks: [RemoteTaskSummary]

    public init(
        version: Int = Self.currentVersion,
        serverName: String,
        generatedAt: Date = Date(),
        tasks: [RemoteTaskSummary]
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.tasks = tasks
    }
}

public struct RemoteTaskFollowUpRequest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let taskID: UUID
    public let idempotencyKey: UUID
    public let text: String
    public let attachments: [RemoteTaskAttachmentDescriptor]
    public let createdAt: Date

    public init(
        version: Int = Self.currentVersion,
        taskID: UUID,
        idempotencyKey: UUID,
        text: String,
        attachments: [RemoteTaskAttachmentDescriptor] = [],
        createdAt: Date = Date()
    ) {
        self.version = version
        self.taskID = taskID
        self.idempotencyKey = idempotencyKey
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

public enum RemoteTaskActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case commit
    case push
    case merge
    case deploy
    case publish
    case release
}

/// The exact consequential action Buddy reviewed. A token is minted only for
/// this binding and cannot authorize another task, action, argument set, or
/// newer task state.
public struct RemoteTaskActionIntent: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let taskID: UUID
    public let action: RemoteTaskActionKind
    public let arguments: [String: String]
    public let expectedReceiptSequence: UInt64?

    public init(
        version: Int = Self.currentVersion,
        taskID: UUID,
        action: RemoteTaskActionKind,
        arguments: [String: String] = [:],
        expectedReceiptSequence: UInt64? = nil
    ) {
        self.version = version
        self.taskID = taskID
        self.action = action
        self.arguments = arguments
        self.expectedReceiptSequence = expectedReceiptSequence
    }

    public var bindingID: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct RemoteTaskPreparedAction: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let intent: RemoteTaskActionIntent
    public let actionToken: String
    public let expiresAt: Date
    public let confirmationSummary: String

    public init(
        version: Int = Self.currentVersion,
        intent: RemoteTaskActionIntent,
        actionToken: String,
        expiresAt: Date,
        confirmationSummary: String
    ) {
        self.version = version
        self.intent = intent
        self.actionToken = actionToken
        self.expiresAt = expiresAt
        self.confirmationSummary = confirmationSummary
    }
}

/// The exact prepared action and its single-use device-bound authorization.
/// Keeping the intent in the execution request lets the Mac recompute the
/// binding instead of trusting a client-supplied action identifier.
public struct RemoteTaskActionExecutionRequest: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let intent: RemoteTaskActionIntent
    public let actionToken: String

    public init(
        version: Int = Self.currentVersion,
        intent: RemoteTaskActionIntent,
        actionToken: String
    ) {
        self.version = version
        self.intent = intent
        self.actionToken = actionToken
    }
}

/// Privacy-preserving APNs metadata. Prompt text, workspace identity,
/// attachment names, provider transcripts, and action tokens never enter it.
public struct RemoteTaskPushSummary: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let taskID: UUID
    public let state: RemoteTaskState
    public let issuedAt: Date
    public let expiresAt: Date

    public init(
        version: Int = Self.currentVersion,
        taskID: UUID,
        state: RemoteTaskState,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.version = version
        self.taskID = taskID
        self.state = state
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt ?? issuedAt.addingTimeInterval(15 * 60)
    }
}
