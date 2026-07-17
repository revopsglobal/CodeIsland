import Foundation

/// A privacy boundary for the Notifications module.
///
/// macOS does not expose another app's Notification Center history through a
/// public API. CodeIsland therefore keeps its own action-required alerts in a
/// distinct section and represents the cross-app provider as unsupported. The
/// normalization pipeline is intentionally provider-agnostic so a future public
/// API can be adopted without changing the remote snapshot contract.
enum SystemNotificationMirror {
    static let unsupportedReason = "macOS does not expose other apps’ Notification Center history through a public API. CodeIsland never reads private notification databases or asks for Full Disk Access."

    enum Origin: Equatable, Sendable {
        case codeIslandAction
        case systemNotification
    }

    enum ProviderState: Equatable, Sendable {
        case ready
        case permissionRequired(String)
        case unsupported(String)

        var message: String? {
            switch self {
            case .ready:
                return nil
            case .permissionRequired(let message), .unsupported(let message):
                return message
            }
        }

        var exposesSystemHistory: Bool {
            self == .ready
        }
    }

    struct Entry: Equatable, Identifiable, Sendable {
        let id: String
        let source: String
        let title: String
        let body: String
        let createdAt: Date
        let origin: Origin
        let sessionID: String?
        let isRedacted: Bool

        init(
            id: String,
            source: String,
            title: String,
            body: String,
            createdAt: Date,
            origin: Origin,
            sessionID: String? = nil,
            isRedacted: Bool = false
        ) {
            self.id = id
            self.source = source
            self.title = title
            self.body = body
            self.createdAt = createdAt
            self.origin = origin
            self.sessionID = sessionID
            self.isRedacted = isRedacted
        }
    }

    struct Group: Equatable, Identifiable, Sendable {
        var id: String { source }
        let source: String
        let entries: [Entry]
    }

    struct Snapshot: Equatable, Sendable {
        let providerState: ProviderState
        let actionRequired: [Entry]
        let systemGroups: [Group]
    }

    static let currentProviderState: ProviderState = .unsupported(unsupportedReason)

    nonisolated static func makeSnapshot(
        candidates: [Entry],
        providerState: ProviderState = currentProviderState,
        now: Date = Date(),
        maximumAge: TimeInterval = 86_400,
        maximumEntries: Int = 30
    ) -> Snapshot {
        let limit = max(0, maximumEntries)
        let oldestAllowed = now.addingTimeInterval(-max(0, maximumAge))
        let newestAllowed = now.addingTimeInterval(300)
        let normalized = candidates
            .filter { $0.createdAt >= oldestAllowed && $0.createdAt <= newestAllowed }
            .map(normalize)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }

        var dedupeKeys = Set<String>()
        let deduplicated = normalized.filter { entry in
            let key: String
            switch entry.origin {
            case .codeIslandAction:
                key = "action:\(entry.sessionID ?? entry.id)"
            case .systemNotification:
                key = "system:\(entry.source.lowercased())\u{1F}\(entry.title.lowercased())\u{1F}\(entry.body.lowercased())"
            }
            return dedupeKeys.insert(key).inserted
        }

        // Human decisions are signal, never noise: reserve capacity for them
        // before filling any remaining slots with passive system history.
        let actionRequired = Array(
            deduplicated.lazy
                .filter { $0.origin == .codeIslandAction }
                .prefix(limit)
        )
        let remainingCapacity = max(0, limit - actionRequired.count)
        let systemEntries: [Entry]
        if providerState.exposesSystemHistory {
            systemEntries = Array(
                deduplicated.lazy
                    .filter { $0.origin == .systemNotification }
                    .prefix(remainingCapacity)
            )
        } else {
            systemEntries = []
        }

        let grouped = Dictionary(grouping: systemEntries, by: \.source)
            .map { source, entries in Group(source: source, entries: entries) }
            .sorted { lhs, rhs in
                let left = lhs.entries.first?.createdAt ?? .distantPast
                let right = rhs.entries.first?.createdAt ?? .distantPast
                if left != right { return left > right }
                return lhs.source.localizedCaseInsensitiveCompare(rhs.source) == .orderedAscending
            }

        return Snapshot(
            providerState: providerState,
            actionRequired: actionRequired,
            systemGroups: grouped
        )
    }

    nonisolated private static func normalize(_ entry: Entry) -> Entry {
        let source = bounded(entry.source, limit: 80, fallback: "Unknown app")
        let title = bounded(entry.title, limit: 120, fallback: "Notification")
        let body = bounded(entry.body, limit: 280, fallback: "")
        let sensitive = containsSensitiveContent("\(title) \(body)")
        return Entry(
            id: bounded(entry.id, limit: 200, fallback: UUID().uuidString),
            source: source,
            title: sensitive ? "Sensitive notification" : title,
            body: sensitive ? "Content hidden for privacy" : body,
            createdAt: entry.createdAt,
            origin: entry.origin,
            sessionID: entry.sessionID.map { bounded($0, limit: 200, fallback: "") },
            isRedacted: sensitive
        )
    }

    nonisolated private static func bounded(
        _ rawValue: String,
        limit: Int,
        fallback: String
    ) -> String {
        let collapsed = rawValue
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let value = collapsed.isEmpty ? fallback : collapsed
        return String(value.prefix(limit))
    }

    nonisolated private static func containsSensitiveContent(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return [
            "verification code", "security code", "one-time code", "one time code",
            "one-time password", "one time password", "passcode", "password", "2fa", " otp ",
        ].contains { lowered.contains($0) }
    }
}
