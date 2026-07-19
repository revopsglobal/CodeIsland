import CryptoKit
import Foundation
import CodeIslandCore

/// Type-erased host runner used by the coordinator so Codex and Claude share
/// one durable lifecycle without sharing their transport details.
@MainActor
struct RemoteTaskProviderRunner {
    let provider: RemoteTaskProvider

    private let availability: () -> Bool
    private let startHandler: (UUID, URL, String, [URL]) throws -> Void
    private let restoreHandler: (UUID, URL, String) throws -> Void
    private let followUpHandler: (UUID, String, [URL]) throws -> Void
    private let cancelHandler: (UUID) throws -> Void
    private let shutdownHandler: () -> Void

    init(
        provider: RemoteTaskProvider,
        isAvailable: @escaping () -> Bool,
        start: @escaping (UUID, URL, String, [URL]) throws -> Void,
        restore: @escaping (UUID, URL, String) throws -> Void,
        followUp: @escaping (UUID, String, [URL]) throws -> Void,
        cancel: @escaping (UUID) throws -> Void,
        shutdown: @escaping () -> Void = {}
    ) {
        self.provider = provider
        availability = isAvailable
        startHandler = start
        restoreHandler = restore
        followUpHandler = followUp
        cancelHandler = cancel
        shutdownHandler = shutdown
    }

    var isAvailable: Bool { availability() }

    func start(taskID: UUID, workspaceURL: URL, prompt: String, attachments: [URL]) throws {
        try startHandler(taskID, workspaceURL, prompt, attachments)
    }

    func restore(taskID: UUID, workspaceURL: URL, sessionID: String) throws {
        try restoreHandler(taskID, workspaceURL, sessionID)
    }

    func followUp(taskID: UUID, text: String, attachments: [URL]) throws {
        try followUpHandler(taskID, text, attachments)
    }

    func cancel(taskID: UUID) throws {
        try cancelHandler(taskID)
    }

    func shutdown() {
        shutdownHandler()
    }
}

@MainActor
final class RemoteTaskCoordinator {
    enum CoordinatorError: LocalizedError, Equatable {
        case unknownTask(UUID)
        case invalidWorkspace(String)
        case providerUnavailable(RemoteTaskProvider)
        case invalidActionToken
        case staleAction
        case unknownAttachment(String)
        case attachmentMismatch(String)
        case unsafeAttachmentWorkspace

        var errorDescription: String? {
            switch self {
            case .unknownTask(let id): return "Remote task \(id.uuidString) does not exist"
            case .invalidWorkspace: return "The selected workspace is no longer available"
            case .providerUnavailable(let provider): return "\(Self.name(provider)) is unavailable on this Mac"
            case .invalidActionToken: return "The exact action approval is invalid or expired"
            case .staleAction: return "The task changed after this action was prepared"
            case .unknownAttachment(let id): return "Attachment \(id) was not declared for this task"
            case .attachmentMismatch(let id): return "Attachment \(id) does not match its declared size or SHA-256"
            case .unsafeAttachmentWorkspace: return "The task attachment workspace is unsafe"
            }
        }

        private static func name(_ provider: RemoteTaskProvider) -> String {
            switch provider {
            case .codex: return "Codex"
            case .claude: return "Claude"
            case .auto: return "Coding provider"
            }
        }
    }

    private let store: RemoteTaskStore
    private let workspaceCatalog: RemoteWorkspaceCatalog
    private let attachmentStore: RemoteTaskAttachmentStore
    private let runners: [RemoteTaskProvider: RemoteTaskProviderRunner]
    private var actionTokens: RemoteActionTokenVault
    private let now: () -> Date
    private var recoveredTaskIDs = Set<UUID>()

    init(
        store: RemoteTaskStore,
        workspaceCatalog: RemoteWorkspaceCatalog,
        attachmentStore: RemoteTaskAttachmentStore,
        codex: RemoteTaskProviderRunner?,
        claude: RemoteTaskProviderRunner?,
        actionTokens: RemoteActionTokenVault = RemoteActionTokenVault(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.workspaceCatalog = workspaceCatalog
        self.attachmentStore = attachmentStore
        self.actionTokens = actionTokens
        self.now = now
        var runners: [RemoteTaskProvider: RemoteTaskProviderRunner] = [:]
        if let codex { runners[.codex] = codex }
        if let claude { runners[.claude] = claude }
        self.runners = runners
    }

    var snapshot: RemoteTaskSnapshot { store.snapshot() }
    var workspaces: [RemoteWorkspaceSummary] { workspaceCatalog.entries.map(\.summary) }

    func task(id: UUID) -> RemoteTaskRecord? { store.task(id: id) }

    func task(idempotencyKey: UUID) -> RemoteTaskRecord? {
        store.tasks.first { $0.request.idempotencyKey == idempotencyKey }
    }

    func snapshot(deviceID: String) -> RemoteTaskSnapshot {
        let current = store.snapshot()
        let ownedIDs = Set(store.tasks.lazy.filter { $0.deviceID == deviceID }.map(\.id))
        return RemoteTaskSnapshot(
            version: current.version,
            serverName: current.serverName,
            generatedAt: current.generatedAt,
            tasks: current.tasks.filter { ownedIDs.contains($0.id) }
        )
    }

    @discardableResult
    func create(request: RemoteTaskCreateRequest, deviceID: String) throws -> RemoteTaskRecord {
        if let existing = store.tasks.first(where: { $0.request.idempotencyKey == request.idempotencyKey }) {
            return existing
        }

        let resolvedProvider = selectProvider(for: request)
        let hostRequest = replacingProvider(request, with: resolvedProvider)
        let record = try store.create(hostRequest, deviceID: deviceID)

        try startIfReady(taskID: record.id)
        return store.task(id: record.id) ?? record
    }

    @discardableResult
    func stageAttachment(taskID: UUID, attachmentID: String, data: Data) throws -> RemoteTaskRecord {
        guard let record = store.task(id: taskID) else { throw CoordinatorError.unknownTask(taskID) }
        guard let descriptor = record.request.attachments.first(where: { $0.id == attachmentID }) else {
            throw CoordinatorError.unknownAttachment(attachmentID)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard Int64(data.count) == descriptor.byteCount,
              digest.caseInsensitiveCompare(descriptor.sha256) == .orderedSame
        else {
            throw CoordinatorError.attachmentMismatch(attachmentID)
        }

        if record.executionStarted != true {
            _ = try attachmentStore.stage(
                data: data,
                taskID: taskID,
                attachmentID: descriptor.id,
                displayName: descriptor.displayName,
                mediaType: descriptor.mediaType
            )
            try startIfReady(taskID: taskID)
        }
        return store.task(id: taskID) ?? record
    }

    /// Reattaches durable nonterminal tasks to provider session identifiers.
    /// It never replays the original prompt, so calling recovery repeatedly
    /// cannot duplicate execution.
    func recover() throws {
        for record in store.tasks where !record.summary.state.isTerminal {
            guard recoveredTaskIDs.insert(record.id).inserted else { continue }
            let provider = record.summary.provider
            guard provider == .codex || provider == .claude,
                  let runner = runners[provider], runner.isAvailable,
                  let workspaceURL = workspaceCatalog.resolve(id: record.summary.workspaceID),
                  let sessionID = record.summary.providerSessionID,
                  !sessionID.isEmpty
            else {
                try appendNeedsYou(
                    taskID: record.id,
                    summary: "Provider state is uncertain after Mac restart"
                )
                continue
            }
            do {
                try runner.restore(taskID: record.id, workspaceURL: workspaceURL, sessionID: sessionID)
                try append(
                    taskID: record.id,
                    kind: .started,
                    state: .working,
                    summary: "Reattached to \(providerName(provider)) after Mac restart",
                    provider: provider,
                    providerSessionID: sessionID
                )
            } catch {
                try appendNeedsYou(
                    taskID: record.id,
                    summary: "Could not safely restore \(providerName(provider)): \(error.localizedDescription)"
                )
            }
        }
    }

    func followUp(taskID: UUID, text: String, attachments: [URL]) throws {
        guard let record = store.task(id: taskID) else { throw CoordinatorError.unknownTask(taskID) }
        guard let runner = runners[record.summary.provider], runner.isAvailable else {
            throw CoordinatorError.providerUnavailable(record.summary.provider)
        }
        try runner.followUp(taskID: taskID, text: text, attachments: attachments)
    }

    @discardableResult
    func followUp(_ request: RemoteTaskFollowUpRequest) throws -> RemoteTaskRecord {
        guard let record = store.task(id: request.taskID) else {
            throw CoordinatorError.unknownTask(request.taskID)
        }
        guard request.attachments.isEmpty else {
            throw CoordinatorError.unknownAttachment(request.attachments[0].id)
        }
        guard try store.claimMutation(taskID: request.taskID, idempotencyKey: request.idempotencyKey) else {
            return record
        }
        do {
            try followUp(taskID: request.taskID, text: request.text, attachments: [])
        } catch {
            try? store.releaseMutation(taskID: request.taskID, idempotencyKey: request.idempotencyKey)
            throw error
        }
        return store.task(id: request.taskID) ?? record
    }

    func cancel(taskID: UUID) throws {
        guard let record = store.task(id: taskID) else { throw CoordinatorError.unknownTask(taskID) }
        guard !record.summary.state.isTerminal else { return }
        if let runner = runners[record.summary.provider], runner.isAvailable {
            try runner.cancel(taskID: taskID)
        }
        if store.task(id: taskID)?.summary.state.isTerminal != true {
            try append(
                taskID: taskID,
                kind: .cancelled,
                state: .cancelled,
                summary: "Task cancelled",
                provider: record.summary.provider,
                providerSessionID: record.summary.providerSessionID
            )
        }
    }

    func shutdown() {
        for runner in runners.values {
            runner.shutdown()
        }
        recoveredTaskIDs.removeAll()
    }

    func prepareAction(
        _ intent: RemoteTaskActionIntent,
        deviceID: String
    ) throws -> RemoteTaskPreparedAction {
        let record = try validatedRecord(for: intent)
        let token = actionTokens.issue(
            requestID: intent.bindingID,
            deviceID: deviceID,
            now: now()
        )
        return RemoteTaskPreparedAction(
            intent: intent,
            actionToken: token.rawValue,
            expiresAt: token.expiresAt,
            confirmationSummary: "\(intent.action.rawValue.capitalized) for \(record.summary.title)"
        )
    }

    func authorizeAction(
        _ intent: RemoteTaskActionIntent,
        actionToken: String,
        deviceID: String
    ) throws {
        _ = try validatedRecord(for: intent)
        guard actionTokens.consume(
            requestID: intent.bindingID,
            deviceID: deviceID,
            token: actionToken,
            now: now()
        ) == .accepted else {
            throw CoordinatorError.invalidActionToken
        }
    }

    private func validatedRecord(for intent: RemoteTaskActionIntent) throws -> RemoteTaskRecord {
        guard let record = store.task(id: intent.taskID) else {
            throw CoordinatorError.unknownTask(intent.taskID)
        }
        if let expected = intent.expectedReceiptSequence,
           expected != record.summary.lastReceiptSequence {
            throw CoordinatorError.staleAction
        }
        return record
    }

    private func selectProvider(for request: RemoteTaskCreateRequest) -> RemoteTaskProvider {
        guard request.provider == .auto else { return request.provider }
        if let workspaceID = request.workspaceID,
           let affinity = store.tasks
            .filter({ $0.summary.workspaceID == workspaceID && $0.summary.provider != .auto })
            .sorted(by: { $0.summary.updatedAt > $1.summary.updatedAt })
            .first?.summary.provider,
           runners[affinity]?.isAvailable == true {
            return affinity
        }
        if runners[.codex]?.isAvailable == true { return .codex }
        if runners[.claude]?.isAvailable == true { return .claude }
        return .codex
    }

    private func replacingProvider(
        _ request: RemoteTaskCreateRequest,
        with provider: RemoteTaskProvider
    ) -> RemoteTaskCreateRequest {
        RemoteTaskCreateRequest(
            version: request.version,
            clientTaskID: request.clientTaskID,
            idempotencyKey: request.idempotencyKey,
            prompt: request.prompt,
            workspaceID: request.workspaceID,
            provider: provider,
            authority: request.authority,
            attachments: request.attachments,
            requestedProof: request.requestedProof,
            createdAt: request.createdAt
        )
    }

    private func startIfReady(taskID: UUID) throws {
        guard let record = store.task(id: taskID), record.executionStarted != true else { return }
        let provider = record.summary.provider
        guard let workspaceURL = workspaceCatalog.resolve(id: record.summary.workspaceID) else {
            try appendNeedsYou(taskID: taskID, summary: "Choose an available Mac workspace")
            return
        }
        guard let runner = runners[provider], runner.isAvailable else {
            try appendNeedsYou(taskID: taskID, summary: "\(providerName(provider)) is unavailable on this Mac")
            return
        }
        guard let stagedAttachments = stagedAttachmentURLs(for: record) else {
            if record.summary.latestSummary != "Waiting for attachments" {
                try append(
                    taskID: taskID,
                    kind: .changed,
                    state: .queued,
                    summary: "Waiting for attachments",
                    provider: provider
                )
            }
            return
        }

        do {
            let attachments = try materialize(
                stagedAttachments,
                descriptors: record.request.attachments,
                taskID: taskID,
                workspaceURL: workspaceURL
            )
            guard try store.markExecutionStarted(taskID: taskID) else { return }
            try runner.start(
                taskID: taskID,
                workspaceURL: workspaceURL,
                prompt: record.request.prompt,
                attachments: attachments
            )
        } catch {
            try append(
                taskID: taskID,
                kind: .failed,
                state: .failed,
                summary: "\(providerName(provider)) could not start: \(error.localizedDescription)",
                provider: provider
            )
        }
    }

    private func stagedAttachmentURLs(for record: RemoteTaskRecord) -> [URL]? {
        var result: [URL] = []
        for descriptor in record.request.attachments {
            guard let url = try? attachmentStore.url(taskID: record.id, attachmentID: descriptor.id) else {
                return nil
            }
            result.append(url)
        }
        return result
    }

    private func materialize(
        _ stagedURLs: [URL],
        descriptors: [RemoteTaskAttachmentDescriptor],
        taskID: UUID,
        workspaceURL: URL
    ) throws -> [URL] {
        guard !stagedURLs.isEmpty else { return [] }
        let fileManager = FileManager.default
        let canonicalWorkspace = RemoteCwdFilter.canonical(workspaceURL)
        let privateRoot = canonicalWorkspace.appendingPathComponent(".codeisland", isDirectory: true)
        let attachmentsRoot = privateRoot.appendingPathComponent("remote-task-attachments", isDirectory: true)
        let taskRoot = attachmentsRoot.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true)
        for directory in [privateRoot, attachmentsRoot, taskRoot] {
            guard RemoteCwdFilter.contains(directory, in: canonicalWorkspace) else {
                throw CoordinatorError.unsafeAttachmentWorkspace
            }
            if fileManager.fileExists(atPath: directory.path) {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    throw CoordinatorError.unsafeAttachmentWorkspace
                }
            } else {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            }
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        return try zip(stagedURLs, descriptors).map { source, descriptor in
            let target = taskRoot.appendingPathComponent(descriptor.id, isDirectory: false)
            guard RemoteCwdFilter.contains(target, in: taskRoot) else {
                throw CoordinatorError.unsafeAttachmentWorkspace
            }
            if fileManager.fileExists(atPath: target.path) {
                let values = try target.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CoordinatorError.unsafeAttachmentWorkspace
                }
            }
            let data = try Data(contentsOf: source, options: [.mappedIfSafe])
            try data.write(to: target, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            return target
        }
    }

    private func appendNeedsYou(taskID: UUID, summary: String) throws {
        try append(taskID: taskID, kind: .needsAnswer, state: .needsYou, summary: summary)
    }

    private func append(
        taskID: UUID,
        kind: RemoteTaskReceiptKind,
        state: RemoteTaskState,
        summary: String,
        provider: RemoteTaskProvider? = nil,
        providerSessionID: String? = nil
    ) throws {
        guard let record = store.task(id: taskID) else { throw CoordinatorError.unknownTask(taskID) }
        try store.append(RemoteTaskReceipt(
            taskID: taskID,
            sequence: record.summary.lastReceiptSequence + 1,
            kind: kind,
            state: state,
            summary: summary,
            observedAt: now(),
            provider: provider,
            providerSessionID: providerSessionID
        ))
    }

    private func providerName(_ provider: RemoteTaskProvider) -> String {
        switch provider {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .auto: return "Coding provider"
        }
    }
}

@MainActor
extension CodexRemoteTaskRunner {
    func providerAdapter(isAvailable: @escaping () -> Bool = { true }) -> RemoteTaskProviderRunner {
        RemoteTaskProviderRunner(
            provider: .codex,
            isAvailable: isAvailable,
            start: { [weak self] in try self?.start(taskID: $0, workspaceURL: $1, prompt: $2, attachments: $3) },
            restore: { [weak self] in try self?.restore(taskID: $0, workspaceURL: $1, threadID: $2) },
            followUp: { [weak self] in try self?.followUp(taskID: $0, text: $1, attachments: $2) },
            cancel: { [weak self] in try self?.stop(taskID: $0) },
            shutdown: { [weak self] in self?.suspend() }
        )
    }
}

@MainActor
extension ClaudeRemoteTaskRunner {
    func providerAdapter(isAvailable: @escaping () -> Bool = { true }) -> RemoteTaskProviderRunner {
        RemoteTaskProviderRunner(
            provider: .claude,
            isAvailable: isAvailable,
            start: { [weak self] in try self?.start(taskID: $0, workspaceURL: $1, prompt: $2, attachments: $3) },
            restore: { [weak self] in try self?.restore(taskID: $0, workspaceURL: $1, sessionID: $2) },
            followUp: { [weak self] in try self?.followUp(taskID: $0, text: $1, attachments: $2) },
            cancel: { [weak self] in try self?.stop(taskID: $0) },
            shutdown: { [weak self] in self?.suspend() }
        )
    }
}
