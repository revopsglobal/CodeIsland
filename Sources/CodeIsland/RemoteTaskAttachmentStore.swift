import CryptoKit
import Foundation
import CodeIslandCore

struct RemoteTaskStagedAttachment: Equatable {
    let descriptor: RemoteTaskAttachmentDescriptor
    let url: URL
    let hasMediaTypeMismatch: Bool

    /// Remote attachments are context, never executables. The store also forces
    /// mode 0600 after every write.
    let isExecutable = false
}

final class RemoteTaskAttachmentStore {
    static let defaultPerFileLimit: Int64 = 25 * 1_024 * 1_024
    static let defaultPerTaskLimit: Int64 = 50 * 1_024 * 1_024

    enum StoreError: LocalizedError, Equatable {
        case invalidAttachmentID
        case invalidDisplayName
        case invalidMediaType
        case fileTooLarge(limit: Int64)
        case taskTooLarge(limit: Int64)
        case unsafeTaskDirectory
        case unsafeAttachmentTarget

        var errorDescription: String? {
            switch self {
            case .invalidAttachmentID: return "Attachment ID is invalid"
            case .invalidDisplayName: return "Attachment name is invalid"
            case .invalidMediaType: return "Attachment media type is invalid"
            case .fileTooLarge(let limit): return "Attachment exceeds the \(limit)-byte file limit"
            case .taskTooLarge(let limit): return "Attachments exceed the \(limit)-byte task limit"
            case .unsafeTaskDirectory: return "Task attachment directory is unsafe"
            case .unsafeAttachmentTarget: return "Attachment target is unsafe"
            }
        }
    }

    private let baseURL: URL
    private let perFileLimit: Int64
    private let perTaskLimit: Int64
    private let fileManager: FileManager

    init(
        baseURL: URL? = nil,
        perFileLimit: Int64 = defaultPerFileLimit,
        perTaskLimit: Int64 = defaultPerTaskLimit,
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL(fileManager: fileManager)
        self.perFileLimit = perFileLimit
        self.perTaskLimit = perTaskLimit
        self.fileManager = fileManager
    }

    func stage(
        data: Data,
        taskID: UUID,
        attachmentID: String,
        displayName: String,
        mediaType: String
    ) throws -> RemoteTaskStagedAttachment {
        guard Self.isValidAttachmentID(attachmentID) else { throw StoreError.invalidAttachmentID }
        guard Self.isValidDisplayName(displayName) else { throw StoreError.invalidDisplayName }
        let normalizedMediaType = mediaType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isValidMediaType(normalizedMediaType) else { throw StoreError.invalidMediaType }
        guard Int64(data.count) <= perFileLimit else { throw StoreError.fileTooLarge(limit: perFileLimit) }

        let taskURL = try secureTaskDirectory(taskID: taskID)
        let destination = taskURL.appendingPathComponent(attachmentID, isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                throw StoreError.unsafeAttachmentTarget
            }
        }
        guard RemoteCwdFilter.contains(destination, in: taskURL) else {
            throw StoreError.unsafeAttachmentTarget
        }

        let existingSize = Self.fileSize(at: destination, fileManager: fileManager)
        let total = try taskByteCount(taskURL: taskURL) - existingSize + Int64(data.count)
        guard total <= perTaskLimit else { throw StoreError.taskTooLarge(limit: perTaskLimit) }

        try data.write(to: destination, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let stored = try Data(contentsOf: destination, options: [.mappedIfSafe])
        let digest = SHA256.hash(data: stored).map { String(format: "%02x", $0) }.joined()
        let descriptor = RemoteTaskAttachmentDescriptor(
            id: attachmentID,
            displayName: displayName,
            byteCount: Int64(stored.count),
            mediaType: normalizedMediaType,
            sha256: digest
        )
        return RemoteTaskStagedAttachment(
            descriptor: descriptor,
            url: destination,
            hasMediaTypeMismatch: Self.hasMediaTypeMismatch(
                displayName: displayName,
                mediaType: normalizedMediaType
            )
        )
    }

    func url(taskID: UUID, attachmentID: String) throws -> URL {
        guard Self.isValidAttachmentID(attachmentID) else { throw StoreError.invalidAttachmentID }
        let taskURL = try secureTaskDirectory(taskID: taskID)
        let destination = taskURL.appendingPathComponent(attachmentID)
        guard RemoteCwdFilter.contains(destination, in: taskURL),
              fileManager.fileExists(atPath: destination.path),
              (try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])).isSymbolicLink != true
        else { throw StoreError.unsafeAttachmentTarget }
        return destination
    }

    func cleanup(taskID: UUID) throws {
        let taskURL = baseURL.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true)
        guard RemoteCwdFilter.contains(taskURL, in: baseURL) else { throw StoreError.unsafeTaskDirectory }
        if fileManager.fileExists(atPath: taskURL.path) {
            try fileManager.removeItem(at: taskURL)
        }
    }

    private func secureTaskDirectory(taskID: UUID) throws -> URL {
        try fileManager.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseURL.path)
        let taskURL = baseURL.appendingPathComponent(taskID.uuidString.lowercased(), isDirectory: true)
        if fileManager.fileExists(atPath: taskURL.path) {
            let values = try taskURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else {
                throw StoreError.unsafeTaskDirectory
            }
        } else {
            try fileManager.createDirectory(
                at: taskURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard RemoteCwdFilter.contains(taskURL, in: baseURL) else { throw StoreError.unsafeTaskDirectory }
        return taskURL
    }

    private func taskByteCount(taskURL: URL) throws -> Int64 {
        let contents = try fileManager.contentsOfDirectory(
            at: taskURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try contents.reduce(Int64(0)) { total, url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let number = try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            return 0
        }
        return number.int64Value
    }

    private static func isValidAttachmentID(_ value: String) -> Bool {
        guard (1...100).contains(value.utf8.count), value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
    }

    private static func isValidDisplayName(_ value: String) -> Bool {
        let decoded = value.removingPercentEncoding ?? value
        guard (1...180).contains(value.utf8.count),
              !value.hasPrefix("/"),
              decoded != ".", decoded != "..",
              !decoded.contains("/"), !decoded.contains("\\"),
              !decoded.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        return true
    }

    private static func isValidMediaType(_ value: String) -> Bool {
        guard (3...100).contains(value.utf8.count), value.contains("/") else { return false }
        return !value.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func hasMediaTypeMismatch(displayName: String, mediaType: String) -> Bool {
        let ext = URL(fileURLWithPath: displayName).pathExtension.lowercased()
        let expected: [String: Set<String>] = [
            "txt": ["text/plain"],
            "md": ["text/markdown", "text/plain"],
            "csv": ["text/csv", "text/plain"],
            "json": ["application/json", "text/json"],
            "png": ["image/png"],
            "jpg": ["image/jpeg"],
            "jpeg": ["image/jpeg"],
            "pdf": ["application/pdf"],
            "zip": ["application/zip", "application/x-zip-compressed"],
            "sh": ["text/x-shellscript", "application/x-sh"],
        ]
        guard let accepted = expected[ext] else { return false }
        return !accepted.contains(mediaType)
    }

    private static func defaultBaseURL(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return root
            .appendingPathComponent("CodeIsland", isDirectory: true)
            .appendingPathComponent("Remote Tasks", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }
}
