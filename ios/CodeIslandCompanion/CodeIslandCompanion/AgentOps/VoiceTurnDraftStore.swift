import CryptoKit
import Foundation
import Security

struct VoiceTurnDraft: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let request: AgentOpsTurnRequest
    let createdAt: Date
    var lastAttemptAt: Date?
}

enum VoiceTurnDraftStoreError: LocalizedError, Equatable {
    case invalidRequest
    case encryptionUnavailable
    case corruptStorage
    case unknownDraft
    case incompleteServerResult

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "That voice request cannot be saved."
        case .encryptionUnavailable:
            return "Private offline storage is unavailable."
        case .corruptStorage:
            return "Private offline requests could not be read."
        case .unknownDraft:
            return "That offline request no longer exists."
        case .incompleteServerResult:
            return "AgentOps did not return a completed result."
        }
    }
}

@MainActor
final class VoiceTurnDraftStore {
    private struct PersistedState: Codable {
        let version: Int
        let drafts: [VoiceTurnDraft]
    }

    private(set) var drafts: [VoiceTurnDraft] = []
    private let snapshotURL: URL
    private let key: SymmetricKey
    private let fileManager: FileManager
    private let now: () -> Date

    init(
        snapshotURL: URL? = nil,
        key: SymmetricKey? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) throws {
        let root = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("CodeIsland", isDirectory: true)
            .appendingPathComponent("AgentOps Voice", isDirectory: true)
            ?? fileManager.temporaryDirectory
                .appendingPathComponent("CodeIsland AgentOps Voice", isDirectory: true)
        self.snapshotURL = snapshotURL ?? root.appendingPathComponent("turns.enc")
        self.fileManager = fileManager
        self.now = now
        self.key = try key ?? KeychainVoiceTurnDraftKey.loadOrCreate()
        try load()
    }

    @discardableResult
    func save(_ request: AgentOpsTurnRequest) throws -> VoiceTurnDraft {
        let transcript = request.transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !transcript.isEmpty,
            transcript.utf8.count <= 32_000,
            request.idempotencyKey == request.turnID
        else {
            throw VoiceTurnDraftStoreError.invalidRequest
        }
        if let existing = drafts.first(where: {
            $0.request.idempotencyKey == request.idempotencyKey
        }) {
            return existing
        }
        let draft = VoiceTurnDraft(
            id: request.idempotencyKey,
            request: request,
            createdAt: now(),
            lastAttemptAt: nil
        )
        var updated = drafts
        updated.append(draft)
        try persist(updated)
        drafts = updated
        return draft
    }

    func replayRequest(for draftID: UUID) -> AgentOpsTurnRequest? {
        drafts.first(where: { $0.id == draftID })?.request
    }

    func markAttempted(draftID: UUID) throws {
        guard let index = drafts.firstIndex(where: { $0.id == draftID }) else {
            throw VoiceTurnDraftStoreError.unknownDraft
        }
        var updated = drafts
        updated[index].lastAttemptAt = now()
        try persist(updated)
        drafts = updated
    }

    func finish(
        draftID: UUID,
        result: AgentOpsTurnResult
    ) throws {
        guard drafts.contains(where: { $0.id == draftID }) else {
            throw VoiceTurnDraftStoreError.unknownDraft
        }
        if result.kind == .durableWork, result.task == nil {
            throw VoiceTurnDraftStoreError.incompleteServerResult
        }
        let completed = drafts.filter { $0.id != draftID }
        try persist(completed)
        drafts = completed
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        do {
            let encrypted = try Data(contentsOf: snapshotURL)
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let cleartext = try AES.GCM.open(box, using: key)
            let state = try JSONDecoder.agentOps.decode(
                PersistedState.self,
                from: cleartext
            )
            guard state.version == 1 else {
                throw VoiceTurnDraftStoreError.corruptStorage
            }
            drafts = state.drafts
        } catch let error as VoiceTurnDraftStoreError {
            throw error
        } catch {
            throw VoiceTurnDraftStoreError.corruptStorage
        }
    }

    private func persist(_ values: [VoiceTurnDraft]) throws {
        let parent = snapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableParent = parent
        try? mutableParent.setResourceValues(resourceValues)

        let cleartext = try JSONEncoder.agentOps.encode(
            PersistedState(version: 1, drafts: values)
        )
        let sealed = try AES.GCM.seal(cleartext, using: key)
        guard let combined = sealed.combined else {
            throw VoiceTurnDraftStoreError.encryptionUnavailable
        }
        try combined.write(
            to: snapshotURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: snapshotURL.path
        )
    }
}

private enum KeychainVoiceTurnDraftKey {
    private static let service =
        "com.revopsglobal.codeisland.buddy.agentops-voice-drafts"
    private static let account = "aes-gcm-v1"

    static func loadOrCreate() throws -> SymmetricKey {
        if let existing = read() {
            return SymmetricKey(data: existing)
        }
        var bytes = Data(count: 32)
        let result = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            throw VoiceTurnDraftStoreError.encryptionUnavailable
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = read() {
            return SymmetricKey(data: existing)
        }
        guard status == errSecSuccess else {
            throw VoiceTurnDraftStoreError.encryptionUnavailable
        }
        return SymmetricKey(data: bytes)
    }

    private static func read() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            data.count == 32
        else { return nil }
        return data
    }
}
