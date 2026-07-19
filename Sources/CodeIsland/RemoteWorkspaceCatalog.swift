import CryptoKit
import Foundation
import CodeIslandCore

enum RemoteWorkspaceSource: String, Codable, Equatable, Sendable {
    case recentSession
    case saved

    fileprivate var rank: Int {
        switch self {
        case .recentSession: return 0
        case .saved: return 1
        }
    }
}

struct RemoteWorkspaceCandidate: Equatable, Sendable {
    let url: URL
    let source: RemoteWorkspaceSource
    let lastUsedAt: Date

    init(url: URL, source: RemoteWorkspaceSource, lastUsedAt: Date = .distantPast) {
        self.url = url
        self.source = source
        self.lastUsedAt = lastUsedAt
    }
}

struct RemoteWorkspaceEntry: Equatable, Identifiable, Sendable {
    let summary: RemoteWorkspaceSummary
    let url: URL
    let source: RemoteWorkspaceSource
    let lastUsedAt: Date

    var id: String { summary.id }
    var name: String { summary.name }
}

enum RemoteWorkspaceMatch: Equatable, Sendable {
    case matched(RemoteWorkspaceEntry)
    case ambiguous([RemoteWorkspaceEntry])
    case noMatch
}

final class RemoteWorkspaceCatalog {
    private(set) var entries: [RemoteWorkspaceEntry]

    private let allowedRoots: [URL]
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(
        allowedRoots: [URL],
        candidates: [RemoteWorkspaceCandidate],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.allowedRoots = allowedRoots.map(RemoteCwdFilter.canonical)
        self.homeDirectory = RemoteCwdFilter.canonical(homeDirectory)
        self.fileManager = fileManager

        var byPath: [String: RemoteWorkspaceEntry] = [:]
        for candidate in candidates {
            guard RemoteCwdFilter.isSafeWorkspace(
                candidate.url,
                allowedRoots: self.allowedRoots,
                homeDirectory: self.homeDirectory,
                fileManager: fileManager
            ) else { continue }
            let canonicalURL = RemoteCwdFilter.canonical(candidate.url)
            let entry = RemoteWorkspaceEntry(
                summary: RemoteWorkspaceSummary(
                    id: Self.opaqueID(for: canonicalURL),
                    name: canonicalURL.lastPathComponent
                ),
                url: canonicalURL,
                source: candidate.source,
                lastUsedAt: candidate.lastUsedAt
            )
            if let existing = byPath[canonicalURL.path] {
                if Self.sortsBefore(entry, existing) {
                    byPath[canonicalURL.path] = entry
                }
            } else {
                byPath[canonicalURL.path] = entry
            }
        }
        entries = byPath.values.sorted(by: Self.sortsBefore)
    }

    func resolve(id: String) -> URL? {
        guard let entry = entries.first(where: { $0.id == id }),
              RemoteCwdFilter.isSafeWorkspace(
                entry.url,
                allowedRoots: allowedRoots,
                homeDirectory: homeDirectory,
                fileManager: fileManager
              ),
              Self.opaqueID(for: RemoteCwdFilter.canonical(entry.url)) == id
        else { return nil }
        return RemoteCwdFilter.canonical(entry.url)
    }

    func match(_ query: String) -> RemoteWorkspaceMatch {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return .noMatch }
        let scored = entries.compactMap { entry -> (RemoteWorkspaceEntry, Int)? in
            let name = entry.name.lowercased()
            let score: Int
            if entry.id.lowercased() == normalized || name == normalized {
                score = 100
            } else if name.hasPrefix(normalized) {
                score = 80
            } else if name.contains(normalized) {
                score = 60
            } else {
                return nil
            }
            return (entry, score)
        }
        guard let best = scored.map(\.1).max() else { return .noMatch }
        let winners = scored.filter { $0.1 == best }.map(\.0)
        if winners.count == 1, let winner = winners.first {
            return .matched(winner)
        }
        return .ambiguous(winners)
    }

    private static func sortsBefore(_ lhs: RemoteWorkspaceEntry, _ rhs: RemoteWorkspaceEntry) -> Bool {
        if lhs.source.rank != rhs.source.rank { return lhs.source.rank < rhs.source.rank }
        if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
        if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func opaqueID(for url: URL) -> String {
        SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
