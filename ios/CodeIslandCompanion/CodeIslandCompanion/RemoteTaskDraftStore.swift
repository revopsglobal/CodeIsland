import CryptoKit
import Foundation

enum RemoteTaskDraftLocalState: String, Codable, Equatable, Sendable {
    case waitingForMac = "waiting-for-mac"
}

struct RemoteTaskDraftAttachmentInput: Equatable {
    let url: URL
    let displayName: String
    let mediaType: String

    init(url: URL, displayName: String? = nil, mediaType: String) {
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.mediaType = mediaType
    }
}

struct RemoteTaskDraftInput: Equatable {
    let clientTaskID: UUID
    let idempotencyKey: UUID
    let prompt: String
    let workspaceID: String?
    let provider: RemoteTaskProvider
    let requestedProof: String?
    let attachments: [RemoteTaskDraftAttachmentInput]
    let createdAt: Date

    init(
        clientTaskID: UUID = UUID(),
        idempotencyKey: UUID = UUID(),
        prompt: String,
        workspaceID: String?,
        provider: RemoteTaskProvider,
        requestedProof: String? = nil,
        attachments: [RemoteTaskDraftAttachmentInput] = [],
        createdAt: Date = Date()
    ) {
        self.clientTaskID = clientTaskID
        self.idempotencyKey = idempotencyKey
        self.prompt = prompt
        self.workspaceID = workspaceID
        self.provider = provider
        self.requestedProof = requestedProof
        self.attachments = attachments
        self.createdAt = createdAt
    }
}

struct RemoteTaskDraftAttachment: Codable, Equatable, Identifiable {
    let descriptor: RemoteTaskAttachmentDescriptor
    var uploaded: Bool

    var id: String { descriptor.id }
}

struct RemoteTaskDraft: Codable, Equatable, Identifiable {
    let id: UUID
    let request: RemoteTaskCreateRequest
    var attachments: [RemoteTaskDraftAttachment]
    var hostTaskID: UUID?
    let localState: RemoteTaskDraftLocalState
    var updatedAt: Date

    var visibleID: UUID { request.clientTaskID }
}

@MainActor
final class RemoteTaskDraftStore {
    enum StoreError: LocalizedError, Equatable {
        case emptyPrompt
        case invalidAttachment
        case fileTooLarge
        case taskTooLarge
        case unknownDraft
        case unknownAttachment
        case unsafeStorage

        var errorDescription: String? {
            switch self {
            case .emptyPrompt: return "Describe what you want the Mac to do"
            case .invalidAttachment: return "An attachment name or media type is invalid"
            case .fileTooLarge: return "Each attachment must be 25 MB or smaller"
            case .taskTooLarge: return "Task attachments must total 50 MB or less"
            case .unknownDraft: return "The local task draft no longer exists"
            case .unknownAttachment: return "The local task attachment no longer exists"
            case .unsafeStorage: return "The private task draft directory is unsafe"
            }
        }
    }

    private struct PersistedState: Codable {
        let version: Int
        let drafts: [RemoteTaskDraft]
    }

    private static let perFileLimit = 25 * 1_024 * 1_024
    private static let perTaskLimit = 50 * 1_024 * 1_024

    private(set) var drafts: [RemoteTaskDraft] = []
    private let snapshotURL: URL
    private let attachmentDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        snapshotURL: URL? = nil,
        attachmentDirectory: URL? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CodeIsland", isDirectory: true)
            .appendingPathComponent("Remote Task Drafts", isDirectory: true)
            ?? fileManager.temporaryDirectory.appendingPathComponent("CodeIsland Remote Task Drafts", isDirectory: true)
        self.snapshotURL = snapshotURL ?? root.appendingPathComponent("drafts.json")
        self.attachmentDirectory = attachmentDirectory ?? root.appendingPathComponent("Attachments", isDirectory: true)
        self.fileManager = fileManager
        self.now = now
        load()
    }

    @discardableResult
    func enqueue(_ input: RemoteTaskDraftInput) throws -> RemoteTaskDraft {
        let prompt = input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.utf8.count <= 60_000 else { throw StoreError.emptyPrompt }
        if let existing = drafts.first(where: { $0.request.idempotencyKey == input.idempotencyKey }) {
            return existing
        }

        try secureDirectory(attachmentDirectory)
        let draftID = input.clientTaskID
        let draftDirectory = attachmentDirectory.appendingPathComponent(draftID.uuidString.lowercased(), isDirectory: true)
        try secureDirectory(draftDirectory, parent: attachmentDirectory)
        var totalBytes = 0
        var storedAttachments: [RemoteTaskDraftAttachment] = []

        do {
            for source in input.attachments {
                guard Self.validDisplayName(source.displayName), Self.validMediaType(source.mediaType) else {
                    throw StoreError.invalidAttachment
                }
                let values = try source.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw StoreError.invalidAttachment
                }
                let data = try Data(contentsOf: source.url, options: [.mappedIfSafe])
                guard data.count <= Self.perFileLimit else { throw StoreError.fileTooLarge }
                totalBytes += data.count
                guard totalBytes <= Self.perTaskLimit else { throw StoreError.taskTooLarge }

                let attachmentID = "attachment-\(UUID().uuidString.lowercased())"
                let destination = draftDirectory.appendingPathComponent(attachmentID, isDirectory: false)
                guard Self.contains(destination, in: draftDirectory) else { throw StoreError.unsafeStorage }
                try data.write(to: destination, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                storedAttachments.append(RemoteTaskDraftAttachment(
                    descriptor: RemoteTaskAttachmentDescriptor(
                        id: attachmentID,
                        displayName: source.displayName,
                        byteCount: Int64(data.count),
                        mediaType: source.mediaType.lowercased(),
                        sha256: digest
                    ),
                    uploaded: false
                ))
            }

            let request = RemoteTaskCreateRequest(
                clientTaskID: input.clientTaskID,
                idempotencyKey: input.idempotencyKey,
                prompt: prompt,
                workspaceID: input.workspaceID,
                provider: input.provider,
                authority: .editAndTest,
                attachments: storedAttachments.map(\.descriptor),
                requestedProof: input.requestedProof,
                createdAt: input.createdAt
            )
            let draft = RemoteTaskDraft(
                id: draftID,
                request: request,
                attachments: storedAttachments,
                hostTaskID: nil,
                localState: .waitingForMac,
                updatedAt: now()
            )
            var updated = drafts
            updated.append(draft)
            try persist(updated)
            drafts = updated
            return draft
        } catch {
            try? fileManager.removeItem(at: draftDirectory)
            throw error
        }
    }

    func markAccepted(draftID: UUID, hostTaskID: UUID) throws {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else { throw StoreError.unknownDraft }
        var updated = drafts
        updated[index].hostTaskID = hostTaskID
        updated[index].updatedAt = now()
        try persist(updated)
        drafts = updated
    }

    func markAttachmentUploaded(draftID: UUID, attachmentID: String) throws {
        guard let draftIndex = drafts.firstIndex(where: { $0.id == draftID }) else { throw StoreError.unknownDraft }
        guard let attachmentIndex = drafts[draftIndex].attachments.firstIndex(where: { $0.id == attachmentID }) else {
            throw StoreError.unknownAttachment
        }
        var updated = drafts
        updated[draftIndex].attachments[attachmentIndex].uploaded = true
        updated[draftIndex].updatedAt = now()
        try persist(updated)
        drafts = updated
    }

    func finishIfUploaded(draftID: UUID) throws {
        guard let draft = drafts.first(where: { $0.id == draftID }) else { throw StoreError.unknownDraft }
        guard draft.hostTaskID != nil, draft.attachments.allSatisfy(\.uploaded) else { return }
        let updated = drafts.filter { $0.id != draftID }
        try persist(updated)
        drafts = updated
        let directory = attachmentDirectory.appendingPathComponent(draftID.uuidString.lowercased(), isDirectory: true)
        if Self.contains(directory, in: attachmentDirectory) {
            try? fileManager.removeItem(at: directory)
        }
    }

    func attachmentURL(draftID: UUID, attachmentID: String) throws -> URL {
        guard let draft = drafts.first(where: { $0.id == draftID }),
              draft.attachments.contains(where: { $0.id == attachmentID })
        else { throw StoreError.unknownAttachment }
        let directory = attachmentDirectory.appendingPathComponent(draftID.uuidString.lowercased(), isDirectory: true)
        let url = directory.appendingPathComponent(attachmentID, isDirectory: false)
        guard Self.contains(url, in: directory), fileManager.fileExists(atPath: url.path) else {
            throw StoreError.unknownAttachment
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.unsafeStorage }
        return url
    }

    private func load() {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        do {
            let state = try Self.decoder.decode(PersistedState.self, from: Data(contentsOf: snapshotURL))
            guard state.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            drafts = state.drafts
        } catch {
            let quarantine = snapshotURL.appendingPathExtension("corrupt-\(Int(now().timeIntervalSince1970))")
            try? fileManager.moveItem(at: snapshotURL, to: quarantine)
            drafts = []
        }
    }

    private func persist(_ drafts: [RemoteTaskDraft]) throws {
        try secureDirectory(snapshotURL.deletingLastPathComponent())
        let data = try Self.encoder.encode(PersistedState(version: 1, drafts: drafts))
        try data.write(to: snapshotURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
    }

    private func secureDirectory(_ directory: URL, parent: URL? = nil) throws {
        if let parent, !Self.contains(directory, in: parent) { throw StoreError.unsafeStorage }
        if fileManager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw StoreError.unsafeStorage }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: parent == nil,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    private static func contains(_ child: URL, in parent: URL) -> Bool {
        let root = parent.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = child.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func validDisplayName(_ value: String) -> Bool {
        let decoded = value.removingPercentEncoding ?? value
        return (1...180).contains(value.utf8.count)
            && !value.hasPrefix("/")
            && decoded != "." && decoded != ".."
            && !decoded.contains("/") && !decoded.contains("\\")
            && !decoded.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validMediaType(_ value: String) -> Bool {
        (3...100).contains(value.utf8.count)
            && value.contains("/")
            && !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.sortedKeys]
        return value
    }()

    private static let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()
}
