import Foundation

/// A parsed JSON-RPC envelope received from the Codex app-server.
///
/// The Codex transport is newline-delimited JSON; the fields below match
/// JSON-RPC 2.0 with a tolerant reading of responses (the server omits the
/// `jsonrpc` marker on successful replies, which is fine for clients).
public struct CodexJSONRPCMessage: Equatable {
    public enum Kind: Equatable {
        case request(method: String, id: CodexRequestID)
        case notification(method: String)
        case response(id: CodexRequestID)
        case error(id: CodexRequestID?, code: Int, message: String)
    }

    public let raw: [String: AnyCodableLike]
    public let kind: Kind

    public init(raw: [String: AnyCodableLike], kind: Kind) {
        self.raw = raw
        self.kind = kind
    }
}

/// Matches JSON-RPC's union type for request/response ids: int or string.
public enum CodexRequestID: Hashable {
    case int(Int64)
    case string(String)

    public static func decode(_ value: Any?) -> CodexRequestID? {
        if let n = value as? Int { return .int(Int64(n)) }
        if let n = value as? Int64 { return .int(n) }
        if let n = value as? NSNumber { return .int(n.int64Value) }
        if let s = value as? String { return .string(s) }
        return nil
    }

    public var jsonValue: Any {
        switch self {
        case .int(let n): return NSNumber(value: n)
        case .string(let s): return s
        }
    }
}

/// Lightweight, untyped wrapper around `Any` so message records round-trip
/// through `Equatable` without forcing the full schema to be modeled here.
public enum AnyCodableLike: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyCodableLike])
    case object([String: AnyCodableLike])

    public static func from(_ value: Any?) -> AnyCodableLike {
        switch value {
        case nil: return .null
        case let v as NSNull: _ = v; return .null
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() { return .bool(v.boolValue) }
            if CFNumberIsFloatType(v) { return .double(v.doubleValue) }
            return .int(v.int64Value)
        case let v as Bool: return .bool(v)
        case let v as Int: return .int(Int64(v))
        case let v as Int64: return .int(v)
        case let v as Double: return .double(v)
        case let v as String: return .string(v)
        case let v as [Any]: return .array(v.map(AnyCodableLike.from))
        case let v as [String: Any]:
            var out: [String: AnyCodableLike] = [:]
            for (k, val) in v { out[k] = AnyCodableLike.from(val) }
            return .object(out)
        default: return .null
        }
    }

    public var asObject: [String: AnyCodableLike]? {
        if case .object(let o) = self { return o }
        return nil
    }
    public var asArray: [AnyCodableLike]? {
        if case .array(let values) = self { return values }
        return nil
    }
    public var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public var asInt: Int64? {
        if case .int(let value) = self { return value }
        return nil
    }
}

/// Minimal transport surface used by higher-level Codex task runners. Keeping
/// this protocol at the framing boundary makes request correlation testable
/// without spawning a real app-server process.
public protocol CodexAppServerSending: AnyObject {
    @discardableResult
    func sendRequest(method: String, params: Any?) throws -> CodexRequestID
    func sendResponse(id: CodexRequestID, result: Any?) throws
}

public extension CodexAppServerSending {
    /// Start a thread with the immutable CodeIsland Edit & Test boundary.
    @discardableResult
    func startThread(cwd: String, developerInstructions: String) throws -> CodexRequestID {
        try sendRequest(method: "thread/start", params: [
            "cwd": cwd,
            "developerInstructions": developerInstructions,
            "approvalPolicy": "on-request",
            "approvalsReviewer": "user",
            "sandbox": "workspace-write",
            "runtimeWorkspaceRoots": [cwd],
            "environments": [Any](),
            "config": [
                "sandbox_workspace_write": [
                    "network_access": false,
                ],
            ],
        ])
    }

    /// Start a turn using only schema-backed input variants. Images use the
    /// dedicated local-image input; other staged files are explicit mentions.
    @discardableResult
    func startTurn(
        threadID: String,
        text: String,
        attachments: [URL],
        clientUserMessageID: String? = nil,
        workspaceURL: URL? = nil
    ) throws -> CodexRequestID {
        var input: [[String: Any]] = [[
            "type": "text",
            "text": text,
            "text_elements": [Any](),
        ]]
        for attachment in attachments {
            let path = attachment.standardizedFileURL.path
            if Self.codexImageExtensions.contains(attachment.pathExtension.lowercased()) {
                input.append(["type": "localImage", "path": path])
            } else {
                input.append([
                    "type": "mention",
                    "name": attachment.lastPathComponent,
                    "path": path,
                ])
            }
        }

        var params: [String: Any] = [
            "threadId": threadID,
            "input": input,
            "approvalPolicy": "on-request",
            "approvalsReviewer": "user",
            "environments": [Any](),
        ]
        if let clientUserMessageID, !clientUserMessageID.isEmpty {
            params["clientUserMessageId"] = clientUserMessageID
        }
        if let workspaceURL {
            let path = workspaceURL.standardizedFileURL.path
            params["cwd"] = path
            params["runtimeWorkspaceRoots"] = [path]
            params["sandboxPolicy"] = [
                "type": "workspaceWrite",
                "writableRoots": [path],
                "networkAccess": false,
                "excludeSlashTmp": false,
                "excludeTmpdirEnvVar": false,
            ]
        }
        return try sendRequest(method: "turn/start", params: params)
    }

    @discardableResult
    func interrupt(threadID: String, turnID: String) throws -> CodexRequestID {
        try sendRequest(method: "turn/interrupt", params: [
            "threadId": threadID,
            "turnId": turnID,
        ])
    }

    private static var codexImageExtensions: Set<String> {
        ["png", "jpg", "jpeg", "gif", "webp"]
    }
}

/// Client lifecycle / connection errors surfaced to callers.
public enum CodexAppServerError: Error, Equatable {
    case executableMissing(String)
    case processLaunchFailed(String)
    case notConnected
    case writeFailed(String)
}

/// Spawns `codex app-server` as a subprocess and speaks newline-delimited
/// JSON-RPC 2.0 to it. The client is intentionally minimal — framing +
/// dispatch only — so higher-level notifications can be mapped to vibe-notch
/// session state wherever the caller chooses.
///
/// Thread safety: `start`, `stop`, `sendRequest`, and `sendNotification` can
/// be called from any thread; I/O is serialized on an internal dispatch queue.
/// Handler closures run on the caller-supplied callback queue (default: main).
public final class CodexAppServerClient: CodexAppServerSending, @unchecked Sendable {
    public typealias MessageHandler = @Sendable (CodexJSONRPCMessage) -> Void
    public typealias ExitHandler = @Sendable (Int32) -> Void

    public let executableURL: URL
    public let arguments: [String]
    private let callbackQueue: DispatchQueue
    private let ioQueue: DispatchQueue

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var readBuffer: Data = Data()
    private var nextRequestId: Int64 = 1
    private var isStopped: Bool = true

    public var onMessage: MessageHandler?
    public var onExit: ExitHandler?

    public init(
        executableURL: URL = URL(fileURLWithPath: CodexAppServerClient.defaultExecutablePath),
        arguments: [String] = ["app-server", "--listen", "stdio://"],
        callbackQueue: DispatchQueue = .main
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.callbackQueue = callbackQueue
        self.ioQueue = DispatchQueue(label: "com.codeisland.codex-app-server-io")
    }

    /// Default location of the Codex binary bundled with the desktop app.
    public static let defaultExecutablePath = "/Applications/Codex.app/Contents/Resources/codex"

    public var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return process?.isRunning == true
    }

    // MARK: - Lifecycle

    public func start() throws {
        lock.lock()
        if process?.isRunning == true {
            lock.unlock()
            return
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            lock.unlock()
            throw CodexAppServerError.executableMissing(executableURL.path)
        }

        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.standardInput = stdinPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.ioQueue.async { self?.ingest(data: data) }
        }
        // Drain stderr to avoid filling the pipe buffer. We don't route it anywhere
        // by default; users who want the diagnostic stream can hook onto .onExit and
        // read the handle separately.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        proc.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            self?.ioQueue.async { self?.handleProcessExit(status: status) }
        }

        do {
            try proc.run()
        } catch {
            lock.unlock()
            throw CodexAppServerError.processLaunchFailed("\(error)")
        }

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.readBuffer.removeAll(keepingCapacity: true)
        self.isStopped = false
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        isStopped = true
        let proc = process
        let stdin = stdinHandle
        process = nil
        stdinHandle = nil
        lock.unlock()

        try? stdin?.close()
        if let proc, proc.isRunning {
            proc.terminate()
        }
    }

    // MARK: - Send

    /// Send a JSON-RPC request and return the id used.
    @discardableResult
    public func sendRequest(method: String, params: Any? = nil) throws -> CodexRequestID {
        let id: Int64
        lock.lock()
        id = nextRequestId
        nextRequestId &+= 1
        lock.unlock()

        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
        ]
        if let params { body["params"] = params }
        try writeEnvelope(body)
        return .int(id)
    }

    public func sendNotification(method: String, params: Any? = nil) throws {
        var body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]
        if let params { body["params"] = params }
        try writeEnvelope(body)
    }

    /// Reply to a server-to-client JSON-RPC *request* (the server sends these for
    /// e.g. `item/tool/requestUserInput`). The `id` must echo the request's id.
    /// `result` is JSON-serializable (Dictionary/Array/scalar) or nil for `{}`.
    public func sendResponse(id: CodexRequestID, result: Any?) throws {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id.jsonValue,
            "result": result ?? [String: Any](),
        ]
        try writeEnvelope(body)
    }

    /// Send `initialize` with a minimal ClientInfo payload. Codex always expects
    /// this before any other thread / turn calls will work.
    @discardableResult
    public func initializeHandshake(clientName: String, clientVersion: String) throws -> CodexRequestID {
        return try sendRequest(method: "initialize", params: [
            "clientInfo": ["name": clientName, "version": clientVersion],
            "capabilities": NSNull()
        ])
    }

    private func writeEnvelope(_ body: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        var payload = data
        payload.append(0x0A)  // newline terminator

        lock.lock()
        guard !isStopped, let handle = stdinHandle else {
            lock.unlock()
            throw CodexAppServerError.notConnected
        }
        lock.unlock()

        do {
            try handle.write(contentsOf: payload)
        } catch {
            throw CodexAppServerError.writeFailed("\(error)")
        }
    }

    // MARK: - Receive

    private func ingest(data: Data) {
        readBuffer.append(data)
        let parsed = CodexAppServerClient.drainMessages(buffer: &readBuffer)
        guard !parsed.isEmpty else { return }
        for message in parsed {
            let handler = self.onMessage
            callbackQueue.async { handler?(message) }
        }
    }

    private func handleProcessExit(status: Int32) {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        isStopped = true
        process = nil
        stdinHandle = nil
        let handler = onExit
        lock.unlock()
        callbackQueue.async { handler?(status) }
    }

    // MARK: - Pure parser (exposed for tests)

    /// Consume as many complete newline-delimited JSON messages as possible
    /// from the buffer. Trailing partial bytes remain in the buffer untouched.
    public static func drainMessages(buffer: inout Data) -> [CodexJSONRPCMessage] {
        var results: [CodexJSONRPCMessage] = []
        let newline: UInt8 = 0x0A
        var searchStart = buffer.startIndex

        while searchStart < buffer.endIndex {
            guard let newlineIndex = buffer[searchStart..<buffer.endIndex].firstIndex(of: newline) else {
                break
            }
            let lineBytes = buffer[searchStart..<newlineIndex]
            if !lineBytes.isEmpty, let parsed = parseMessage(Data(lineBytes)) {
                results.append(parsed)
            }
            searchStart = buffer.index(after: newlineIndex)
        }

        if searchStart == buffer.startIndex { return results }
        if searchStart >= buffer.endIndex {
            buffer.removeAll(keepingCapacity: true)
        } else {
            buffer = Data(buffer[searchStart..<buffer.endIndex])
        }
        return results
    }

    /// Turn a single JSON object string into a `CodexJSONRPCMessage`, or return
    /// nil when the payload is not a recognizable envelope.
    public static func parseMessage(_ data: Data) -> CodexJSONRPCMessage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let raw = AnyCodableLike.from(obj).asObject ?? [:]

        if let errorPayload = obj["error"] as? [String: Any] {
            let code = (errorPayload["code"] as? Int)
                ?? (errorPayload["code"] as? NSNumber).map(\.intValue)
                ?? 0
            let message = (errorPayload["message"] as? String) ?? ""
            return CodexJSONRPCMessage(
                raw: raw,
                kind: .error(id: CodexRequestID.decode(obj["id"]), code: code, message: message)
            )
        }

        if let method = obj["method"] as? String {
            if let id = CodexRequestID.decode(obj["id"]) {
                return CodexJSONRPCMessage(raw: raw, kind: .request(method: method, id: id))
            } else {
                return CodexJSONRPCMessage(raw: raw, kind: .notification(method: method))
            }
        }

        if let id = CodexRequestID.decode(obj["id"]) {
            return CodexJSONRPCMessage(raw: raw, kind: .response(id: id))
        }
        return nil
    }
}
