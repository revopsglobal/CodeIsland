import Combine
import Foundation
import CodeIslandCore

struct RemoteTaskRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let request: RemoteTaskCreateRequest
    let deviceID: String
    var summary: RemoteTaskSummary
}

@MainActor
final class RemoteTaskStore: ObservableObject {
    enum StoreError: LocalizedError, Equatable {
        case unknownTask(UUID)
        case nonMonotonicReceipt(expected: UInt64, actual: UInt64)

        var errorDescription: String? {
            switch self {
            case .unknownTask(let id):
                return "Remote task \(id.uuidString) does not exist"
            case .nonMonotonicReceipt(let expected, let actual):
                return "Expected receipt sequence \(expected), received \(actual)"
            }
        }
    }

    private struct PersistedState: Codable {
        static let currentVersion = 1

        let version: Int
        let tasks: [RemoteTaskRecord]

        init(version: Int = Self.currentVersion, tasks: [RemoteTaskRecord]) {
            self.version = version
            self.tasks = tasks
        }
    }

    @Published private(set) var tasks: [RemoteTaskRecord] = []

    private let snapshotURL: URL
    private let receiptsURL: URL
    private let serverName: String
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        snapshotURL: URL? = nil,
        receiptsURL: URL? = nil,
        serverName: String = Host.current().localizedName ?? "CodeIsland Mac",
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        let defaultDirectory = Self.defaultDirectory(fileManager: fileManager)
        self.snapshotURL = snapshotURL ?? defaultDirectory.appendingPathComponent("tasks.json")
        self.receiptsURL = receiptsURL ?? defaultDirectory.appendingPathComponent("receipts.jsonl")
        self.serverName = serverName
        self.fileManager = fileManager
        self.now = now
        load()
    }

    @discardableResult
    func create(_ request: RemoteTaskCreateRequest, deviceID: String) throws -> RemoteTaskRecord {
        if let existing = tasks.first(where: { $0.request.idempotencyKey == request.idempotencyKey }) {
            return existing
        }

        let sanitizedRequest = Self.sanitized(request)
        let taskID = UUID()
        let timestamp = now()
        let workspaceID = sanitizedRequest.workspaceID ?? ""
        let record = RemoteTaskRecord(
            id: taskID,
            request: sanitizedRequest,
            deviceID: deviceID,
            summary: RemoteTaskSummary(
                id: taskID,
                clientTaskID: sanitizedRequest.clientTaskID,
                idempotencyKey: sanitizedRequest.idempotencyKey,
                title: Self.title(from: sanitizedRequest.prompt),
                workspaceID: workspaceID,
                workspaceName: workspaceID.isEmpty ? "Choose workspace" : workspaceID,
                provider: sanitizedRequest.provider,
                authority: sanitizedRequest.authority,
                state: .queued,
                createdAt: sanitizedRequest.createdAt,
                updatedAt: timestamp,
                lastReceiptSequence: 1,
                latestSummary: "Accepted by Mac"
            )
        )
        let accepted = RemoteTaskReceipt(
            taskID: taskID,
            sequence: 1,
            kind: .accepted,
            state: .queued,
            summary: "Accepted by Mac",
            observedAt: timestamp,
            provider: sanitizedRequest.provider
        )

        try appendToLedger(accepted)
        let updatedTasks = tasks + [record]
        try persist(updatedTasks)
        tasks = updatedTasks
        return record
    }

    func append(_ receipt: RemoteTaskReceipt) throws {
        guard let index = tasks.firstIndex(where: { $0.id == receipt.taskID }) else {
            throw StoreError.unknownTask(receipt.taskID)
        }
        let expected = tasks[index].summary.lastReceiptSequence + 1
        guard receipt.sequence == expected else {
            throw StoreError.nonMonotonicReceipt(expected: expected, actual: receipt.sequence)
        }

        let safeReceipt = Self.sanitized(receipt)
        var updatedTasks = tasks
        updatedTasks[index].summary = updatedTasks[index].summary.applying(safeReceipt)
        try appendToLedger(safeReceipt)
        try persist(updatedTasks)
        tasks = updatedTasks
    }

    func task(id: UUID) -> RemoteTaskRecord? {
        tasks.first(where: { $0.id == id })
    }

    func snapshot() -> RemoteTaskSnapshot {
        RemoteTaskSnapshot(
            serverName: serverName,
            generatedAt: now(),
            tasks: tasks.map(\.summary).sorted { $0.updatedAt > $1.updatedAt }
        )
    }

    private func load() {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        do {
            let data = try Data(contentsOf: snapshotURL)
            let state = try Self.decoder.decode(PersistedState.self, from: data)
            guard state.version == PersistedState.currentVersion else {
                throw CocoaError(.coderReadCorrupt)
            }
            tasks = replayLedger(over: state.tasks)
        } catch {
            quarantineCorruptSnapshot()
            tasks = []
        }
    }

    private func replayLedger(over records: [RemoteTaskRecord]) -> [RemoteTaskRecord] {
        guard let data = try? Data(contentsOf: receiptsURL), !data.isEmpty else { return records }
        var recovered = records
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let receipt = try? Self.decoder.decode(RemoteTaskReceipt.self, from: Data(line)),
                  let index = recovered.firstIndex(where: { $0.id == receipt.taskID }),
                  receipt.sequence == recovered[index].summary.lastReceiptSequence + 1
            else { continue }
            recovered[index].summary = recovered[index].summary.applying(receipt)
        }
        return recovered
    }

    private func appendToLedger(_ receipt: RemoteTaskReceipt) throws {
        let directory = receiptsURL.deletingLastPathComponent()
        try secureDirectory(directory)
        if !fileManager.fileExists(atPath: receiptsURL.path) {
            guard fileManager.createFile(
                atPath: receiptsURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: receiptsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try Self.ledgerEncoder.encode(receipt)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptsURL.path)
    }

    private func persist(_ records: [RemoteTaskRecord]) throws {
        let retained = Self.retainedRecords(records)
        let data = try Self.snapshotEncoder.encode(PersistedState(tasks: retained))
        try secureDirectory(snapshotURL.deletingLastPathComponent())
        try data.write(to: snapshotURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
    }

    private func secureDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private func quarantineCorruptSnapshot() {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        let suffix = formatter.string(from: now())
        let quarantineURL = snapshotURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(snapshotURL.lastPathComponent).corrupt-\(suffix)")
        try? fileManager.moveItem(at: snapshotURL, to: quarantineURL)
    }

    private static func retainedRecords(_ records: [RemoteTaskRecord]) -> [RemoteTaskRecord] {
        let active = records.filter { !$0.summary.state.isTerminal }
        let terminal = records
            .filter { $0.summary.state.isTerminal }
            .sorted { $0.summary.updatedAt > $1.summary.updatedAt }
        return active + terminal.prefix(200)
    }

    private static func title(from prompt: String) -> String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? "New coding task" : String(firstLine.prefix(120))
    }

    private static func sanitized(_ request: RemoteTaskCreateRequest) -> RemoteTaskCreateRequest {
        RemoteTaskCreateRequest(
            version: request.version,
            clientTaskID: request.clientTaskID,
            idempotencyKey: request.idempotencyKey,
            prompt: redact(request.prompt),
            workspaceID: request.workspaceID,
            provider: request.provider,
            authority: request.authority,
            attachments: request.attachments,
            requestedProof: request.requestedProof.map(redact),
            createdAt: request.createdAt
        )
    }

    private static func sanitized(_ receipt: RemoteTaskReceipt) -> RemoteTaskReceipt {
        RemoteTaskReceipt(
            version: receipt.version,
            eventID: receipt.eventID,
            taskID: receipt.taskID,
            sequence: receipt.sequence,
            kind: receipt.kind,
            state: receipt.state,
            summary: redact(receipt.summary),
            observedAt: receipt.observedAt,
            provider: receipt.provider,
            providerSessionID: receipt.providerSessionID.map(redact),
            evidence: receipt.evidence.map(sanitized)
        )
    }

    private static func sanitized(_ evidence: RemoteTaskEvidence) -> RemoteTaskEvidence {
        RemoteTaskEvidence(
            branch: evidence.branch.map(redact),
            changedFiles: evidence.changedFiles.map {
                RemoteTaskChangedFile(
                    path: redact($0.path),
                    kind: $0.kind,
                    previousPath: $0.previousPath.map(redact)
                )
            },
            checks: evidence.checks.map {
                RemoteTaskCheck(
                    command: redact($0.command),
                    exitCode: $0.exitCode,
                    summary: redact($0.summary),
                    durationSeconds: $0.durationSeconds
                )
            },
            warnings: evidence.warnings.map(redact),
            sourceState: evidence.sourceState
        )
    }

    private static func redact(_ input: String) -> String {
        let patterns = [
            #"(?i)\bbearer\s+[^\s\"';,]+"#,
            #"(?i)\b(?:action[-_ ]?token|authorization)\s*[:=]\s*[^\s\"';,]+"#,
        ]
        return patterns.reduce(input) { result, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return result }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            return expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("CodeIsland", isDirectory: true)
            .appendingPathComponent("Remote Tasks", isDirectory: true)
    }

    private static let snapshotEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let ledgerEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
