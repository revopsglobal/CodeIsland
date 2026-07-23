import Foundation
import CodeIslandCore

struct CodexRemoteTaskAttention: Equatable {
    enum Kind: Equatable {
        case approval
        case permissions
        case question
    }

    let kind: Kind
    let taskID: UUID
    let requestID: CodexRequestID
    let threadID: String
    let turnID: String
    let detail: String
}

@MainActor
final class CodexRemoteTaskRunner {
    enum RunnerError: LocalizedError, Equatable {
        case unknownTask(UUID)
        case alreadyStarted(UUID)
        case missingThread(UUID)
        case missingActiveTurn(UUID)
        case unknownApproval

        var errorDescription: String? {
            switch self {
            case .unknownTask(let id): return "Remote task \(id.uuidString) does not exist"
            case .alreadyStarted(let id): return "Remote task \(id.uuidString) already has a Codex thread"
            case .missingThread(let id): return "Remote task \(id.uuidString) has no Codex thread"
            case .missingActiveTurn(let id): return "Remote task \(id.uuidString) has no active Codex turn"
            case .unknownApproval: return "The Codex approval is no longer pending"
            }
        }
    }

    private struct Context {
        let taskID: UUID
        let workspaceURL: URL
        var threadID: String?
        var activeTurnID: String?
    }

    private enum PendingRequest {
        case threadStart(taskID: UUID, prompt: String, attachments: [URL])
        case turnStart(taskID: UUID)
        case interrupt(taskID: UUID)

        var taskID: UUID {
            switch self {
            case .threadStart(let taskID, _, _), .turnStart(let taskID), .interrupt(let taskID):
                return taskID
            }
        }
    }

    private struct PendingApproval {
        let taskID: UUID
    }

    private let sender: CodexAppServerSending
    private let store: RemoteTaskStore
    private let onAttention: (CodexRemoteTaskAttention) -> Void
    private var contexts: [UUID: Context] = [:]
    private var taskIDsByThread: [String: UUID] = [:]
    private var pendingRequests: [CodexRequestID: PendingRequest] = [:]
    private var pendingApprovals: [CodexRequestID: PendingApproval] = [:]

    init(
        sender: CodexAppServerSending,
        store: RemoteTaskStore,
        onAttention: @escaping (CodexRemoteTaskAttention) -> Void = { _ in }
    ) {
        self.sender = sender
        self.store = store
        self.onAttention = onAttention
    }

    func start(taskID: UUID, workspaceURL: URL, prompt: String, attachments: [URL]) throws {
        guard store.task(id: taskID) != nil else { throw RunnerError.unknownTask(taskID) }
        guard contexts[taskID] == nil else { throw RunnerError.alreadyStarted(taskID) }
        let canonicalWorkspace = RemoteCwdFilter.canonical(workspaceURL)
        let policy = RemoteTaskExecutionPolicy(workspaceURL: canonicalWorkspace)
        contexts[taskID] = Context(
            taskID: taskID,
            workspaceURL: canonicalWorkspace,
            threadID: nil,
            activeTurnID: nil
        )
        let requestID = try sender.startThread(
            cwd: canonicalWorkspace.path,
            developerInstructions: policy.codexConfiguration.developerInstructions
        )
        pendingRequests[requestID] = .threadStart(
            taskID: taskID,
            prompt: prompt,
            attachments: attachments
        )
    }

    func restore(taskID: UUID, workspaceURL: URL, threadID: String) throws {
        guard store.task(id: taskID) != nil else { throw RunnerError.unknownTask(taskID) }
        guard contexts[taskID] == nil else { throw RunnerError.alreadyStarted(taskID) }
        let canonicalWorkspace = RemoteCwdFilter.canonical(workspaceURL)
        contexts[taskID] = Context(
            taskID: taskID,
            workspaceURL: canonicalWorkspace,
            threadID: threadID,
            activeTurnID: nil
        )
        taskIDsByThread[threadID] = taskID
    }

    func suspend() {
        contexts.removeAll()
        taskIDsByThread.removeAll()
        pendingRequests.removeAll()
        pendingApprovals.removeAll()
    }

    func followUp(taskID: UUID, text: String, attachments: [URL]) throws {
        guard let context = contexts[taskID], let threadID = context.threadID else {
            throw RunnerError.missingThread(taskID)
        }
        let requestID = try sender.startTurn(
            threadID: threadID,
            text: text,
            attachments: attachments,
            workspaceURL: context.workspaceURL
        )
        pendingRequests[requestID] = .turnStart(taskID: taskID)
    }

    func stop(taskID: UUID) throws {
        guard let context = contexts[taskID], let threadID = context.threadID else {
            throw RunnerError.missingThread(taskID)
        }
        guard let turnID = context.activeTurnID else {
            throw RunnerError.missingActiveTurn(taskID)
        }
        let requestID = try sender.interrupt(threadID: threadID, turnID: turnID)
        pendingRequests[requestID] = .interrupt(taskID: taskID)
    }

    func resolveApproval(requestID: CodexRequestID, decision: RemoteApprovalDecision) throws {
        guard let pending = pendingApprovals.removeValue(forKey: requestID) else {
            throw RunnerError.unknownApproval
        }
        let wireDecision = decision == .approve ? "accept" : "decline"
        try sender.sendResponse(id: requestID, result: ["decision": wireDecision])
        try appendReceipt(
            taskID: pending.taskID,
            kind: .started,
            state: .working,
            summary: decision == .approve ? "Approved exact action; Codex resumed" : "Denied exact action; Codex resumed"
        )
    }

    func handle(_ message: CodexJSONRPCMessage) {
        switch message.kind {
        case .response(let id):
            handleResponse(id: id, message: message)
        case .error(let id, _, let errorMessage):
            guard let id, let pending = pendingRequests.removeValue(forKey: id) else { return }
            fail(taskID: pending.taskID, summary: "Codex app-server error: \(errorMessage)")
        case .request(let method, let id):
            handleRequest(method: method, id: id, params: message.raw["params"]?.asObject ?? [:])
        case .notification(let method):
            handleNotification(method: method, params: message.raw["params"]?.asObject ?? [:])
        }
    }

    private func handleResponse(id: CodexRequestID, message: CodexJSONRPCMessage) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        let result = message.raw["result"]?.asObject ?? [:]
        do {
            switch pending {
            case .threadStart(let taskID, let prompt, let attachments):
                guard let threadID = result["thread"]?.asObject?["id"]?.asString,
                      var context = contexts[taskID]
                else {
                    fail(taskID: taskID, summary: "Codex did not return a thread ID")
                    return
                }
                context.threadID = threadID
                contexts[taskID] = context
                taskIDsByThread[threadID] = taskID
                guard let task = store.task(id: taskID) else { throw RunnerError.unknownTask(taskID) }
                let turnRequestID = try sender.startTurn(
                    threadID: threadID,
                    text: prompt,
                    attachments: attachments,
                    clientUserMessageID: task.request.idempotencyKey.uuidString.lowercased(),
                    workspaceURL: context.workspaceURL
                )
                pendingRequests[turnRequestID] = .turnStart(taskID: taskID)

            case .turnStart(let taskID):
                guard let turnID = result["turn"]?.asObject?["id"]?.asString,
                      var context = contexts[taskID]
                else {
                    fail(taskID: taskID, summary: "Codex did not return a turn ID")
                    return
                }
                context.activeTurnID = turnID
                contexts[taskID] = context
                try appendReceipt(
                    taskID: taskID,
                    kind: .started,
                    state: .working,
                    summary: "Codex started Edit & Test work"
                )

            case .interrupt:
                // The response only acknowledges the request. `turn/completed`
                // with `interrupted` is the terminal source of truth.
                break
            }
        } catch {
            fail(taskID: pending.taskID, summary: "Codex routing failed: \(error.localizedDescription)")
        }
    }

    private func handleRequest(method: String, id: CodexRequestID, params: [String: AnyCodableLike]) {
        guard let threadID = params["threadId"]?.asString,
              let turnID = params["turnId"]?.asString,
              let taskID = taskIDsByThread[threadID],
              let context = contexts[taskID]
        else { return }

        switch method {
        case "item/commandExecution/requestApproval":
            handleCommandApproval(
                id: id,
                taskID: taskID,
                context: context,
                threadID: threadID,
                turnID: turnID,
                params: params
            )

        case "item/fileChange/requestApproval":
            if let grantRoot = params["grantRoot"]?.asString,
               !RemoteCwdFilter.contains(URL(fileURLWithPath: grantRoot), in: context.workspaceURL) {
                declineAndBlock(
                    id: id,
                    taskID: taskID,
                    threadID: threadID,
                    turnID: turnID,
                    detail: "Codex requested file access outside the selected workspace"
                )
            } else {
                try? sender.sendResponse(id: id, result: ["decision": "accept"])
            }

        case "item/permissions/requestApproval":
            attention(
                kind: .permissions,
                taskID: taskID,
                requestID: id,
                threadID: threadID,
                turnID: turnID,
                detail: params["reason"]?.asString ?? "Codex requested additional permissions"
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsApproval,
                state: .needsYou,
                summary: "Additional permission needs your review"
            )

        case "item/tool/requestUserInput":
            let question = params["questions"]?.asArray?.first?.asObject?["question"]?.asString
                ?? "Codex needs an answer"
            attention(
                kind: .question,
                taskID: taskID,
                requestID: id,
                threadID: threadID,
                turnID: turnID,
                detail: question
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsAnswer,
                state: .needsYou,
                summary: "Codex needs your answer"
            )

        default:
            break
        }
    }

    private func handleCommandApproval(
        id: CodexRequestID,
        taskID: UUID,
        context: Context,
        threadID: String,
        turnID: String,
        params: [String: AnyCodableLike]
    ) {
        if let cwd = params["cwd"]?.asString,
           !RemoteCwdFilter.contains(URL(fileURLWithPath: cwd), in: context.workspaceURL) {
            declineAndBlock(
                id: id,
                taskID: taskID,
                threadID: threadID,
                turnID: turnID,
                detail: "Codex requested a command outside the selected workspace"
            )
            return
        }

        let command = params["command"]?.asString ?? ""
        let policy = RemoteTaskExecutionPolicy(workspaceURL: context.workspaceURL)
        switch policy.decision(for: .shell(command, origin: .provider)) {
        case .allow:
            try? sender.sendResponse(id: id, result: ["decision": "accept"])
        case .needsApproval:
            pendingApprovals[id] = PendingApproval(taskID: taskID)
            attention(
                kind: .approval,
                taskID: taskID,
                requestID: id,
                threadID: threadID,
                turnID: turnID,
                detail: command.isEmpty ? "Codex requested a consequential command" : command
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsApproval,
                state: .needsYou,
                summary: "A consequential Codex action needs your approval"
            )
        case .deny:
            declineAndBlock(
                id: id,
                taskID: taskID,
                threadID: threadID,
                turnID: turnID,
                detail: "Codex requested an action denied by Edit & Test policy"
            )
        }
    }

    private func declineAndBlock(
        id: CodexRequestID,
        taskID: UUID,
        threadID: String,
        turnID: String,
        detail: String
    ) {
        try? sender.sendResponse(id: id, result: ["decision": "decline"])
        attention(
            kind: .approval,
            taskID: taskID,
            requestID: id,
            threadID: threadID,
            turnID: turnID,
            detail: detail
        )
        try? appendReceipt(
            taskID: taskID,
            kind: .needsApproval,
            state: .needsYou,
            summary: detail
        )
    }

    private func handleNotification(method: String, params: [String: AnyCodableLike]) {
        guard let threadID = params["threadId"]?.asString,
              let taskID = taskIDsByThread[threadID]
        else { return }

        switch method {
        case "item/completed":
            handleCompletedItem(taskID: taskID, item: params["item"]?.asObject ?? [:])
        case "turn/completed":
            let turn = params["turn"]?.asObject ?? [:]
            let status = turn["status"]?.asString
            guard var context = contexts[taskID],
                  let turnID = turn["id"]?.asString,
                  context.activeTurnID == turnID
            else { return }
            context.activeTurnID = nil
            contexts[taskID] = context
            switch status {
            case "completed":
                try? appendReceipt(
                    taskID: taskID,
                    kind: .finished,
                    state: .verified,
                    summary: "Codex completed the requested Edit & Test turn"
                )
            case "interrupted":
                try? appendReceipt(
                    taskID: taskID,
                    kind: .cancelled,
                    state: .cancelled,
                    summary: "Codex turn was interrupted"
                )
            case "failed":
                let detail = turn["error"]?.asObject?["message"]?.asString ?? "Codex turn failed"
                fail(taskID: taskID, summary: detail)
            default:
                break
            }
        default:
            break
        }
    }

    private func handleCompletedItem(taskID: UUID, item: [String: AnyCodableLike]) {
        guard let type = item["type"]?.asString else { return }
        switch type {
        case "fileChange":
            try? appendReceipt(
                taskID: taskID,
                kind: .changed,
                state: .working,
                summary: "Codex applied workspace file changes"
            )
        case "commandExecution":
            guard let command = item["command"]?.asString,
                  isVerificationCommand(command),
                  let exitCodeValue = item["exitCode"]?.asInt,
                  let exitCode = Int(exactly: exitCodeValue)
            else { return }
            let duration = item["durationMs"]?.asInt.map { Double($0) / 1_000 }
            let check = RemoteTaskCheck(
                command: command,
                exitCode: exitCode,
                summary: exitCode == 0 ? "Passed" : "Failed",
                durationSeconds: duration
            )
            let oldEvidence = store.task(id: taskID)?.summary.evidence ?? RemoteTaskEvidence()
            let evidence = RemoteTaskEvidence(
                branch: oldEvidence.branch,
                changedFiles: oldEvidence.changedFiles,
                checks: oldEvidence.checks + [check],
                warnings: oldEvidence.warnings,
                sourceState: oldEvidence.sourceState
            )
            try? appendReceipt(
                taskID: taskID,
                kind: exitCode == 0 ? .tested : .failed,
                state: exitCode == 0 ? .working : .failed,
                summary: exitCode == 0 ? "Verification passed" : "Verification failed",
                evidence: evidence
            )
        default:
            break
        }
    }

    private func isVerificationCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return [" test", "test ", " test\n", "build", "lint", "check", "analyze", "pytest"]
            .contains { lower.contains($0) }
            || lower == "swift test"
            || lower.hasSuffix(" test")
    }

    private func attention(
        kind: CodexRemoteTaskAttention.Kind,
        taskID: UUID,
        requestID: CodexRequestID,
        threadID: String,
        turnID: String,
        detail: String
    ) {
        onAttention(CodexRemoteTaskAttention(
            kind: kind,
            taskID: taskID,
            requestID: requestID,
            threadID: threadID,
            turnID: turnID,
            detail: detail
        ))
    }

    private func appendReceipt(
        taskID: UUID,
        kind: RemoteTaskReceiptKind,
        state: RemoteTaskState,
        summary: String,
        evidence: RemoteTaskEvidence? = nil
    ) throws {
        guard let task = store.task(id: taskID) else { throw RunnerError.unknownTask(taskID) }
        guard !task.summary.state.isTerminal else {
            finishContext(taskID: taskID)
            return
        }
        let providerSessionID = contexts[taskID]?.threadID
        try store.append(RemoteTaskReceipt(
            taskID: taskID,
            sequence: task.summary.lastReceiptSequence + 1,
            kind: kind,
            state: state,
            summary: summary,
            provider: .codex,
            providerSessionID: providerSessionID,
            evidence: evidence
        ))
        if state.isTerminal {
            finishContext(taskID: taskID)
        }
    }

    private func fail(taskID: UUID, summary: String) {
        try? appendReceipt(taskID: taskID, kind: .failed, state: .failed, summary: summary)
    }

    private func finishContext(taskID: UUID) {
        if let threadID = contexts.removeValue(forKey: taskID)?.threadID,
           taskIDsByThread[threadID] == taskID {
            taskIDsByThread.removeValue(forKey: threadID)
        }
        pendingRequests = pendingRequests.filter { $0.value.taskID != taskID }
        pendingApprovals = pendingApprovals.filter { $0.value.taskID != taskID }
    }
}
