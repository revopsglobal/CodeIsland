import Foundation

struct SharedDraftFileInput: Equatable {
    let data: Data
    let displayName: String
    let mediaType: String
}

struct SharedDraftAttachment: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let mediaType: String
    let byteCount: Int64

    var fileName: String { id }
}

struct SharedTaskDraftManifest: Codable, Equatable, Identifiable {
    static let currentVersion = 1

    let version: Int
    let id: UUID
    let text: String
    let createdAt: Date
    let attachments: [SharedDraftAttachment]

    init(
        version: Int = Self.currentVersion,
        id: UUID,
        text: String,
        createdAt: Date,
        attachments: [SharedDraftAttachment]
    ) {
        self.version = version
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
    }
}

struct ClaimedSharedTaskDraft: Equatable {
    let manifest: SharedTaskDraftManifest
    let attachmentURLs: [URL]
}

final class SharedDraftInbox {
    static let appGroupID = "group.com.revopsglobal.codeisland.buddy"

    enum InboxError: LocalizedError, Equatable {
        case appGroupUnavailable
        case emptyDraft
        case invalidFile
        case fileTooLarge
        case draftTooLarge
        case corruptManifest
        case unsafePath

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: return "The private CodeIsland share inbox is unavailable"
            case .emptyDraft: return "Share text, a link, image, or file"
            case .invalidFile: return "A shared file name or media type is invalid"
            case .fileTooLarge: return "Each shared file must be 25 MB or smaller"
            case .draftTooLarge: return "Shared files must total 50 MB or less"
            case .corruptManifest: return "The shared draft could not be read"
            case .unsafePath: return "The shared draft path is unsafe"
            }
        }
    }

    private static let fileLimit = 25 * 1_024 * 1_024
    private static let draftLimit = 50 * 1_024 * 1_024

    private let rootURL: URL
    private let fileManager: FileManager
    private let now: () -> Date

    convenience init(fileManager: FileManager = .default) throws {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else { throw InboxError.appGroupUnavailable }
        try self.init(
            rootURL: container.appendingPathComponent("Shared Task Inbox", isDirectory: true),
            fileManager: fileManager
        )
    }

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.now = now
        try secureDirectory(self.rootURL)
    }

    @discardableResult
    func store(
        id: UUID = UUID(),
        text: String?,
        files: [SharedDraftFileInput]
    ) throws -> SharedTaskDraftManifest {
        let cleanText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty || !files.isEmpty else { throw InboxError.emptyDraft }

        let directory = draftDirectory(id)
        let manifestURL = directory.appendingPathComponent("manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return try readManifest(at: manifestURL)
        }

        try secureDirectory(directory, inside: rootURL)
        var total = 0
        var attachments: [SharedDraftAttachment] = []
        do {
            for input in files {
                guard Self.validName(input.displayName), Self.validMediaType(input.mediaType) else {
                    throw InboxError.invalidFile
                }
                guard input.data.count <= Self.fileLimit else { throw InboxError.fileTooLarge }
                total += input.data.count
                guard total <= Self.draftLimit else { throw InboxError.draftTooLarge }

                let fileID = "shared-\(UUID().uuidString.lowercased())"
                let destination = directory.appendingPathComponent(fileID)
                guard Self.contains(destination, in: directory) else { throw InboxError.unsafePath }
                try input.data.write(to: destination, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
                attachments.append(SharedDraftAttachment(
                    id: fileID,
                    displayName: input.displayName,
                    mediaType: input.mediaType.lowercased(),
                    byteCount: Int64(input.data.count)
                ))
            }

            let manifest = SharedTaskDraftManifest(
                id: id,
                text: cleanText,
                createdAt: now(),
                attachments: attachments
            )
            let data = try Self.encoder.encode(manifest)
            try data.write(to: manifestURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
            return manifest
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func claimNext() throws -> ClaimedSharedTaskDraft? {
        let manifests = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { directory -> SharedTaskDraftManifest? in
            guard Self.contains(directory, in: rootURL) else { return nil }
            return try? readManifest(at: directory.appendingPathComponent("manifest.json"))
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard let manifest = manifests.first else { return nil }
        let directory = draftDirectory(manifest.id)
        let urls = try manifest.attachments.map { attachment -> URL in
            let url = directory.appendingPathComponent(attachment.fileName)
            guard Self.contains(url, in: directory), fileManager.fileExists(atPath: url.path) else {
                throw InboxError.corruptManifest
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw InboxError.unsafePath
            }
            return url
        }
        return ClaimedSharedTaskDraft(manifest: manifest, attachmentURLs: urls)
    }

    func acknowledge(_ id: UUID) throws {
        let directory = draftDirectory(id)
        guard Self.contains(directory, in: rootURL) else { throw InboxError.unsafePath }
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func readManifest(at url: URL) throws -> SharedTaskDraftManifest {
        guard Self.contains(url, in: rootURL),
              let manifest = try? Self.decoder.decode(
                SharedTaskDraftManifest.self,
                from: Data(contentsOf: url)
              ),
              manifest.version == SharedTaskDraftManifest.currentVersion
        else { throw InboxError.corruptManifest }
        return manifest
    }

    private func draftDirectory(_ id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func secureDirectory(_ url: URL, inside parent: URL? = nil) throws {
        if let parent, !Self.contains(url, in: parent) { throw InboxError.unsafePath }
        if fileManager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw InboxError.unsafePath }
        } else {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: parent == nil,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private static func contains(_ child: URL, in parent: URL) -> Bool {
        let root = parent.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = child.standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == root || candidate.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func validName(_ value: String) -> Bool {
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
    }

    private static let encoder: JSONEncoder = {
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
