import CodeIslandCore
import Foundation

struct ClaudeProcessConfiguration: Equatable {
    let executableURL: URL
    let arguments: [String]
    let currentDirectoryURL: URL
}

@MainActor
protocol ClaudeProcessHandling: AnyObject {
    var isRunning: Bool { get }
    func send(line: String) throws
    func terminate()
}

@MainActor
protocol ClaudeProcessLaunching: AnyObject {
    func launch(
        configuration: ClaudeProcessConfiguration,
        onStdoutLine: @escaping (String) -> Void,
        onStderrLine: @escaping (String) -> Void,
        onTermination: @escaping (Int32) -> Void
    ) throws -> ClaudeProcessHandling
}

struct ClaudeExecutableLocator {
    static let defaultsKey = "CodeIslandClaudeExecutablePath"

    static func resolve(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> String? {
        var candidates: [String] = []
        if let explicitPath, !explicitPath.isEmpty { candidates.append(explicitPath) }
        candidates.append(contentsOf: [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            homeDirectoryURL.appendingPathComponent(".local/bin/claude").path,
        ])
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("claude")
                    .path
            })
        }
        var seen = Set<String>()
        return candidates.first { candidate in
            let path = NSString(string: candidate).expandingTildeInPath
            guard seen.insert(path).inserted else { return false }
            return fileManager.isExecutableFile(atPath: path)
        }.map { NSString(string: $0).expandingTildeInPath }
    }
}

struct ClaudeRemoteTaskAttention: Equatable {
    enum Kind: Equatable {
        case approval
        case blocked
        case question
    }

    let kind: Kind
    let taskID: UUID
    let requestID: String
    let toolUseID: String
    let detail: String
}

@MainActor
final class ClaudeRemoteTaskRunner {
    enum RunnerError: LocalizedError, Equatable {
        case unknownTask(UUID)
        case alreadyStarted(UUID)
        case missingExecutable
        case invalidWorkspace
        case attachmentOutsideWorkspace(String)
        case missingSession(UUID)
        case unknownApproval

        var errorDescription: String? {
            switch self {
            case .unknownTask(let id):
                return "Remote task \(id.uuidString) does not exist"
            case .alreadyStarted(let id):
                return "Remote task \(id.uuidString) already has a Claude session"
            case .missingExecutable:
                return "Claude Code is not installed on the Mac"
            case .invalidWorkspace:
                return "The selected workspace is unavailable"
            case .attachmentOutsideWorkspace(let path):
                return "Attachment is outside the selected workspace: \(path)"
            case .missingSession(let id):
                return "Remote task \(id.uuidString) has no resumable Claude session"
            case .unknownApproval:
                return "The Claude approval is no longer pending"
            }
        }
    }

    private struct Context {
        let taskID: UUID
        let workspaceURL: URL
        var sessionID: String
        var process: ClaudeProcessHandling?
        var processGeneration: Int
        var pendingToolUses: [String: ClaudeToolUse]
        var sawResultForCurrentTurn: Bool
        var stoppedByUser: Bool
    }

    private struct PendingApproval {
        let taskID: UUID
        let request: ClaudeControlPermissionRequest
    }

    private let launcher: ClaudeProcessLaunching
    private let store: RemoteTaskStore
    private let executablePath: String?
    private let makeSessionID: () -> String
    private let onAttention: (ClaudeRemoteTaskAttention) -> Void
    private var contexts: [UUID: Context] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]

    init(
        launcher: ClaudeProcessLaunching? = nil,
        store: RemoteTaskStore,
        executablePath: String? = ClaudeExecutableLocator.resolve(),
        sessionID: @escaping () -> String = { UUID().uuidString.lowercased() },
        onAttention: @escaping (ClaudeRemoteTaskAttention) -> Void = { _ in }
    ) {
        self.launcher = launcher ?? FoundationClaudeProcessLauncher()
        self.store = store
        self.executablePath = executablePath
        makeSessionID = sessionID
        self.onAttention = onAttention
    }

    func start(taskID: UUID, workspaceURL: URL, prompt: String, attachments: [URL]) throws {
        guard store.task(id: taskID) != nil else { throw RunnerError.unknownTask(taskID) }
        guard contexts[taskID] == nil else { throw RunnerError.alreadyStarted(taskID) }
        guard let executablePath else { throw RunnerError.missingExecutable }
        let workspace = RemoteCwdFilter.canonical(workspaceURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw RunnerError.invalidWorkspace }
        try validate(attachments: attachments, workspaceURL: workspace)

        let sessionID = makeSessionID()
        contexts[taskID] = Context(
            taskID: taskID,
            workspaceURL: workspace,
            sessionID: sessionID,
            process: nil,
            processGeneration: 0,
            pendingToolUses: [:],
            sawResultForCurrentTurn: false,
            stoppedByUser: false
        )
        do {
            try launchProcess(
                taskID: taskID,
                executablePath: executablePath,
                resume: false,
                firstPrompt: promptWithAttachments(prompt, attachments: attachments)
            )
        } catch {
            contexts.removeValue(forKey: taskID)
            throw error
        }
    }

    func restore(taskID: UUID, workspaceURL: URL, sessionID: String) throws {
        guard store.task(id: taskID) != nil else { throw RunnerError.unknownTask(taskID) }
        guard contexts[taskID] == nil else { throw RunnerError.alreadyStarted(taskID) }
        let workspace = RemoteCwdFilter.canonical(workspaceURL)
        contexts[taskID] = Context(
            taskID: taskID,
            workspaceURL: workspace,
            sessionID: sessionID,
            process: nil,
            processGeneration: 0,
            pendingToolUses: [:],
            sawResultForCurrentTurn: false,
            stoppedByUser: false
        )
    }

    func suspend() {
        for taskID in contexts.keys {
            guard var context = contexts[taskID] else { continue }
            context.stoppedByUser = true
            context.processGeneration += 1
            context.process?.terminate()
            context.process = nil
            contexts[taskID] = context
        }
        pendingApprovals.removeAll()
    }

    func followUp(taskID: UUID, text: String, attachments: [URL]) throws {
        guard var context = contexts[taskID] else { throw RunnerError.missingSession(taskID) }
        try validate(attachments: attachments, workspaceURL: context.workspaceURL)
        let prompt = promptWithAttachments(text, attachments: attachments)
        context.sawResultForCurrentTurn = false
        context.stoppedByUser = false
        contexts[taskID] = context

        if let process = context.process, process.isRunning {
            try process.send(line: Self.userMessageLine(prompt))
            try appendReceipt(
                taskID: taskID,
                kind: .started,
                state: .working,
                summary: "Claude received your follow-up"
            )
            return
        }
        guard let executablePath else { throw RunnerError.missingExecutable }
        try launchProcess(
            taskID: taskID,
            executablePath: executablePath,
            resume: true,
            firstPrompt: prompt
        )
    }

    func stop(taskID: UUID) throws {
        guard var context = contexts[taskID] else { throw RunnerError.missingSession(taskID) }
        context.stoppedByUser = true
        context.process?.terminate()
        context.process = nil
        contexts[taskID] = context
        pendingApprovals = pendingApprovals.filter { $0.value.taskID != taskID }
        try appendReceipt(
            taskID: taskID,
            kind: .cancelled,
            state: .cancelled,
            summary: "Claude task was stopped"
        )
    }

    func resolveApproval(requestID: String, decision: RemoteApprovalDecision) throws {
        guard let pending = pendingApprovals.removeValue(forKey: requestID),
              let process = contexts[pending.taskID]?.process,
              process.isRunning
        else { throw RunnerError.unknownApproval }
        let response: ClaudeControlPermissionResponse
        if decision == .approve {
            response = .allow(requestID: requestID, toolUseID: pending.request.toolUseID)
        } else {
            response = .deny(
                requestID: requestID,
                toolUseID: pending.request.toolUseID,
                message: "Denied from CodeIsland Buddy"
            )
        }
        try process.send(line: response.jsonLine())
        try appendReceipt(
            taskID: pending.taskID,
            kind: .started,
            state: .working,
            summary: decision == .approve
                ? "Approved exact Claude action; work resumed"
                : "Denied exact Claude action; work resumed"
        )
    }

    func handle(_ event: ClaudeStreamEvent, taskID: UUID) {
        guard contexts[taskID] != nil else { return }
        switch event {
        case .initialization(let sessionID, let cwd):
            handleInitialization(taskID: taskID, sessionID: sessionID, cwd: cwd)
        case .assistant(_, let toolUses, _):
            guard var context = contexts[taskID] else { return }
            for toolUse in toolUses { context.pendingToolUses[toolUse.id] = toolUse }
            contexts[taskID] = context
        case .toolResults(let results, _):
            handleToolResults(taskID: taskID, results: results)
        case .controlRequest(let request):
            handlePermissionRequest(taskID: taskID, request: request)
        case .permissionDenied(_, _, let message, _):
            try? appendReceipt(
                taskID: taskID,
                kind: .needsApproval,
                state: .needsYou,
                summary: "Claude permission was denied: \(message)"
            )
        case .result(let result):
            handleResult(taskID: taskID, result: result)
        case .hook, .unknown, .malformed:
            break
        }
    }

    private func launchProcess(
        taskID: UUID,
        executablePath: String,
        resume: Bool,
        firstPrompt: String
    ) throws {
        guard var context = contexts[taskID] else { throw RunnerError.missingSession(taskID) }
        context.processGeneration += 1
        let generation = context.processGeneration
        let configuration = ClaudeProcessConfiguration(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: Self.arguments(
                taskID: taskID,
                sessionID: context.sessionID,
                resume: resume
            ),
            currentDirectoryURL: context.workspaceURL
        )
        let process = try launcher.launch(
            configuration: configuration,
            onStdoutLine: { [weak self] line in
                Task { @MainActor in
                    self?.handleStdout(line, taskID: taskID, generation: generation)
                }
            },
            onStderrLine: { [weak self] line in
                Task { @MainActor in
                    self?.handleStderr(line, taskID: taskID, generation: generation)
                }
            },
            onTermination: { [weak self] status in
                Task { @MainActor in
                    self?.handleTermination(status, taskID: taskID, generation: generation)
                }
            }
        )
        context.process = process
        context.sawResultForCurrentTurn = false
        context.stoppedByUser = false
        contexts[taskID] = context
        try process.send(line: Self.userMessageLine(firstPrompt))
    }

    private func handleStdout(_ line: String, taskID: UUID, generation: Int) {
        guard contexts[taskID]?.processGeneration == generation else { return }
        handle(ClaudeStreamEvent.parse(line: line), taskID: taskID)
    }

    private func handleStderr(_ line: String, taskID: UUID, generation: Int) {
        guard contexts[taskID]?.processGeneration == generation else { return }
        let detail = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return }
        // Claude writes diagnostics to stderr while continuing. The terminal
        // result/exit status remains the authoritative failure boundary.
    }

    private func handleTermination(_ status: Int32, taskID: UUID, generation: Int) {
        guard var context = contexts[taskID], context.processGeneration == generation else { return }
        context.process = nil
        contexts[taskID] = context
        pendingApprovals = pendingApprovals.filter { $0.value.taskID != taskID }
        guard !context.stoppedByUser, !context.sawResultForCurrentTurn else { return }
        fail(
            taskID: taskID,
            summary: status == 0
                ? "Claude exited before returning a result"
                : "Claude exited with status \(status)"
        )
    }

    private func handleInitialization(taskID: UUID, sessionID: String, cwd: String?) {
        guard var context = contexts[taskID] else { return }
        if let cwd {
            let actual = RemoteCwdFilter.canonical(URL(fileURLWithPath: cwd))
            guard actual.path == context.workspaceURL.path else {
                context.process?.terminate()
                contexts[taskID] = context
                fail(taskID: taskID, summary: "Claude initialized outside the selected workspace")
                return
            }
        }
        context.sessionID = sessionID
        contexts[taskID] = context
        try? appendReceipt(
            taskID: taskID,
            kind: .started,
            state: .working,
            summary: "Claude started Edit & Test work"
        )
    }

    private func handlePermissionRequest(taskID: UUID, request: ClaudeControlPermissionRequest) {
        guard let context = contexts[taskID], let process = context.process, process.isRunning else { return }

        if request.requiresUserInteraction {
            attention(
                kind: .question,
                taskID: taskID,
                request: request,
                detail: "Claude needs an interactive answer in the Mac session"
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsAnswer,
                state: .needsYou,
                summary: "Open the Mac session to answer Claude"
            )
            return
        }

        let decision = policyDecision(request: request, workspaceURL: context.workspaceURL)
        switch decision {
        case .allow:
            try? process.send(line: ClaudeControlPermissionResponse.allow(
                requestID: request.requestID,
                toolUseID: request.toolUseID
            ).jsonLine())
        case .needsApproval:
            pendingApprovals[request.requestID] = PendingApproval(taskID: taskID, request: request)
            attention(
                kind: .approval,
                taskID: taskID,
                request: request,
                detail: requestDetail(request)
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsApproval,
                state: .needsYou,
                summary: "A consequential Claude action needs your approval"
            )
        case .deny:
            let message = "Denied by CodeIsland Edit & Test workspace policy"
            try? process.send(line: ClaudeControlPermissionResponse.deny(
                requestID: request.requestID,
                toolUseID: request.toolUseID,
                message: message
            ).jsonLine())
            attention(
                kind: .blocked,
                taskID: taskID,
                request: request,
                detail: request.blockedPath ?? message
            )
            try? appendReceipt(
                taskID: taskID,
                kind: .needsApproval,
                state: .needsYou,
                summary: "Claude was blocked from acting outside the selected workspace"
            )
        }
    }

    private func policyDecision(
        request: ClaudeControlPermissionRequest,
        workspaceURL: URL
    ) -> RemoteTaskExecutionDecision {
        let policy = RemoteTaskExecutionPolicy(workspaceURL: workspaceURL)
        let name = request.toolName.lowercased()
        if let blockedPath = request.blockedPath,
           !RemoteCwdFilter.contains(URL(fileURLWithPath: blockedPath), in: workspaceURL) {
            return .deny
        }
        switch name {
        case "bash":
            guard let command = request.input["command"]?.asString else { return .needsApproval }
            return policy.decision(for: .shell(command, origin: .provider))
        case "read":
            guard let path = path(from: request.input, keys: ["file_path", "path"]) else { return .deny }
            return policy.decision(for: .fileRead(url: resolve(path, in: workspaceURL)))
        case "glob", "grep":
            let path = path(from: request.input, keys: ["path"])
                .map { resolve($0, in: workspaceURL) } ?? workspaceURL
            return policy.decision(for: .fileRead(url: path))
        case "edit", "write", "notebookedit":
            guard let path = path(from: request.input, keys: ["file_path", "notebook_path", "path"]) else {
                return .deny
            }
            return policy.decision(for: .fileChange(url: resolve(path, in: workspaceURL)))
        case "task", "agent":
            // Subagent tool calls carry their own control requests and agent ID,
            // so delegation itself does not expand authority.
            return .allow
        case "websearch", "webfetch":
            return .needsApproval
        default:
            return .needsApproval
        }
    }

    private func handleToolResults(taskID: UUID, results: [ClaudeToolResult]) {
        guard var context = contexts[taskID] else { return }
        for result in results {
            guard let toolUse = context.pendingToolUses.removeValue(forKey: result.toolUseID) else { continue }
            let name = toolUse.name.lowercased()
            if ["edit", "write", "notebookedit"].contains(name), !result.isError {
                try? appendReceipt(
                    taskID: taskID,
                    kind: .changed,
                    state: .working,
                    summary: "Claude applied workspace file changes"
                )
                continue
            }
            if name == "bash",
               let command = toolUse.input["command"]?.asString,
               isVerificationCommand(command),
               let exitCode = result.exitCode {
                let oldEvidence = store.task(id: taskID)?.summary.evidence ?? RemoteTaskEvidence()
                let check = RemoteTaskCheck(
                    command: command,
                    exitCode: exitCode,
                    summary: exitCode == 0 ? "Passed" : "Failed"
                )
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
                    summary: exitCode == 0 ? "Claude verification passed" : "Claude verification failed",
                    evidence: evidence
                )
            }
        }
        contexts[taskID] = context
    }

    private func handleResult(taskID: UUID, result: ClaudeResultEvent) {
        guard var context = contexts[taskID] else { return }
        context.sawResultForCurrentTurn = true
        contexts[taskID] = context
        if result.isError || result.subtype != "success" {
            if !result.permissionDenials.isEmpty {
                try? appendReceipt(
                    taskID: taskID,
                    kind: .needsApproval,
                    state: .needsYou,
                    summary: "Claude stopped on a permission decision"
                )
            } else {
                fail(taskID: taskID, summary: result.result ?? "Claude task failed")
            }
            return
        }
        try? appendReceipt(
            taskID: taskID,
            kind: .finished,
            state: .working,
            summary: "Claude finished; verification evidence is ready for the coordinator"
        )
    }

    private func validate(attachments: [URL], workspaceURL: URL) throws {
        for attachment in attachments where !RemoteCwdFilter.contains(attachment, in: workspaceURL) {
            throw RunnerError.attachmentOutsideWorkspace(attachment.path)
        }
    }

    private func promptWithAttachments(_ prompt: String, attachments: [URL]) -> String {
        guard !attachments.isEmpty else { return prompt }
        let list = attachments.map { "- \($0.path)" }.joined(separator: "\n")
        return "\(prompt)\n\nStaged attachments inside the selected workspace:\n\(list)"
    }

    private static func userMessageLine(_ text: String) throws -> String {
        let object: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": text]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return line
    }

    private static func arguments(taskID: UUID, sessionID: String, resume: Bool) -> [String] {
        let permissionSettings: [String: Any] = [
            "permissions": [
                "ask": [
                    "Bash", "Edit", "Write", "NotebookEdit", "Read", "Glob", "Grep",
                    "WebFetch", "WebSearch", "Task", "Agent",
                ],
            ],
            "sandbox": [
                "enabled": true,
                "autoAllowBashIfSandboxed": false,
            ],
        ]
        let settingsData = try? JSONSerialization.data(
            withJSONObject: permissionSettings,
            options: [.sortedKeys]
        )
        let settings = settingsData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        var arguments = [
            "--print",
            "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--include-hook-events",
            "--permission-prompt-tool", "stdio",
            "--permission-mode", "acceptEdits",
            "--setting-sources", "user,project,local",
            "--settings", settings,
            "--tools", "Bash,Glob,Grep,Read,Edit,Write,NotebookEdit,WebSearch,WebFetch,Task",
            "--name", "CodeIsland-\(taskID.uuidString.prefix(8))",
        ]
        if resume {
            arguments.append(contentsOf: ["--resume", sessionID])
        } else {
            arguments.append(contentsOf: ["--session-id", sessionID])
        }
        return arguments
    }

    private func path(from input: [String: AnyCodableLike], keys: [String]) -> String? {
        keys.lazy.compactMap { input[$0]?.asString }.first
    }

    private func resolve(_ path: String, in workspaceURL: URL) -> URL {
        if path == "~" || path.hasPrefix("~/") {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return workspaceURL.appendingPathComponent(path)
    }

    private func requestDetail(_ request: ClaudeControlPermissionRequest) -> String {
        if let command = request.input["command"]?.asString, !command.isEmpty { return command }
        if let path = path(from: request.input, keys: ["file_path", "notebook_path", "path"]) {
            return "\(request.toolName): \(path)"
        }
        return request.decisionReason ?? "Claude requested \(request.toolName)"
    }

    private func isVerificationCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return [" test", "test ", " test\n", "build", "lint", "check", "analyze", "pytest"]
            .contains { lower.contains($0) }
            || lower == "swift test"
            || lower.hasSuffix(" test")
    }

    private func attention(
        kind: ClaudeRemoteTaskAttention.Kind,
        taskID: UUID,
        request: ClaudeControlPermissionRequest,
        detail: String
    ) {
        onAttention(ClaudeRemoteTaskAttention(
            kind: kind,
            taskID: taskID,
            requestID: request.requestID,
            toolUseID: request.toolUseID,
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
        try store.append(RemoteTaskReceipt(
            taskID: taskID,
            sequence: task.summary.lastReceiptSequence + 1,
            kind: kind,
            state: state,
            summary: summary,
            provider: .claude,
            providerSessionID: contexts[taskID]?.sessionID,
            evidence: evidence
        ))
    }

    private func fail(taskID: UUID, summary: String) {
        try? appendReceipt(taskID: taskID, kind: .failed, state: .failed, summary: summary)
    }
}

@MainActor
final class FoundationClaudeProcessLauncher: ClaudeProcessLaunching {
    func launch(
        configuration: ClaudeProcessConfiguration,
        onStdoutLine: @escaping (String) -> Void,
        onStderrLine: @escaping (String) -> Void,
        onTermination: @escaping (Int32) -> Void
    ) throws -> ClaudeProcessHandling {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = configuration.currentDirectoryURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let outputFramer = ClaudeLineFramer(onLine: onStdoutLine)
        let errorFramer = ClaudeLineFramer(onLine: onStderrLine)
        output.fileHandleForReading.readabilityHandler = { handle in
            outputFramer.consume(handle.availableData)
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            errorFramer.consume(handle.availableData)
        }
        process.terminationHandler = { process in
            output.fileHandleForReading.readabilityHandler = nil
            error.fileHandleForReading.readabilityHandler = nil
            outputFramer.finish()
            errorFramer.finish()
            DispatchQueue.main.async { onTermination(process.terminationStatus) }
        }
        try process.run()
        return FoundationClaudeProcessHandle(process: process, input: input)
    }
}

@MainActor
private final class FoundationClaudeProcessHandle: ClaudeProcessHandling {
    private let process: Process
    private let input: Pipe

    init(process: Process, input: Pipe) {
        self.process = process
        self.input = input
    }

    var isRunning: Bool { process.isRunning }

    func send(line: String) throws {
        guard process.isRunning else { throw CocoaError(.executableNotLoadable) }
        guard let data = (line + "\n").data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func terminate() {
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
    }
}

private final class ClaudeLineFramer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void) {
        self.onLine = onLine
    }

    func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        let lines = drainCompleteLines()
        lock.unlock()
        for line in lines { onLine(line) }
    }

    func finish() {
        lock.lock()
        let final = String(data: buffer, encoding: .utf8)?.trimmingCharacters(in: .newlines)
        buffer.removeAll(keepingCapacity: false)
        lock.unlock()
        if let final, !final.isEmpty { onLine(final) }
    }

    private func drainCompleteLines() -> [String] {
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newline]
            buffer.removeSubrange(...newline)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
