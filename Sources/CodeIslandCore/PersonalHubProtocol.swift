import Foundation

/// The four surfaces shared by the Mac notch, iPhone app, and private web app.
/// `auto` is a requested mode; snapshots always include the concrete resolved mode.
public enum PersonalHubMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case home
    case work
    case code

    public var id: String { rawValue }
}

/// Greg's useful Crest 4.9 capability baseline plus the personal extensions he
/// asked CodeIsland to carry. Pomodoro/focus timers are intentionally excluded.
/// Keeping this in CodeIslandCore prevents the Mac and iPhone from silently
/// drifting into different products.
public enum PersonalHubModuleID: String, Codable, CaseIterable, Identifiable, Sendable {
    // Crest 4.9 catalog
    case nowPlaying
    case shelf
    case calendar
    case reminders
    case notes
    case system
    case weather
    case notifications
    case claude
    case agents
    case github
    case audio
    case bluetooth
    case battery
    case quickToggles

    // Personal parity extensions
    case downloads
    case camera
    case teleprompter
    case windowManager

    public var id: String { rawValue }
}

public enum PersonalHubPlatform: String, Codable, CaseIterable, Sendable {
    case mac
    case iphone
    case web
}

public struct PersonalHubModuleDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: PersonalHubModuleID
    public let title: String
    public let symbol: String
    public let platforms: Set<PersonalHubPlatform>

    public init(
        id: PersonalHubModuleID,
        title: String,
        symbol: String,
        platforms: Set<PersonalHubPlatform> = Set(PersonalHubPlatform.allCases)
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.platforms = platforms
    }
}

public enum PersonalHubAvailability: String, Codable, Equatable, Sendable {
    case ready
    case partial
    case loading
    case permissionRequired
    case unavailable
    case offline
}

public enum PersonalHubActionRole: String, Codable, Equatable, Sendable {
    case normal
    case primary
    case destructive
}

/// An allow-listed action advertised by a module or item. Mutating remote actions
/// receive an exact, short-lived token from the Mac before they can be executed.
public struct PersonalHubAction: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let symbol: String?
    public let role: PersonalHubActionRole
    public let targetID: String?
    public let deepLink: URL?
    /// Optional structured seed data for a device-side editor. The Mac never
    /// trusts this value on its own; the client sends its reviewed value back
    /// through a typed intent and the server revalidates current state.
    public let value: String?
    public let actionToken: String?
    public let actionExpiresAt: Date?

    public init(
        id: String,
        label: String,
        symbol: String? = nil,
        role: PersonalHubActionRole = .normal,
        targetID: String? = nil,
        deepLink: URL? = nil,
        value: String? = nil,
        actionToken: String? = nil,
        actionExpiresAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.role = role
        self.targetID = targetID
        self.deepLink = deepLink
        self.value = value
        self.actionToken = actionToken
        self.actionExpiresAt = actionExpiresAt
    }
}

/// A typed intent is prepared before any remote mutation. The exact encoded
/// intent becomes the binding key for the short-lived, single-use action token.
public struct PersonalHubActionIntent: Codable, Equatable, Sendable {
    public let moduleID: PersonalHubModuleID
    public let actionID: String
    public let targetID: String?
    public let value: String?

    public init(
        moduleID: PersonalHubModuleID,
        actionID: String,
        targetID: String? = nil,
        value: String? = nil
    ) {
        self.moduleID = moduleID
        self.actionID = actionID
        self.targetID = targetID
        self.value = value
    }

    public var bindingID: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return data.base64EncodedString()
    }
}

/// Structured calendar input shared by the native iPhone client, private web
/// client, and the Mac EventKit owner. It is JSON-encoded into an allow-listed
/// action intent so the existing short-lived confirmation token still binds to
/// the exact title, time, duration, and meeting link the person reviewed.
public struct PersonalHubCalendarDraft: Codable, Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let joinURL: URL?
    public let notes: String?

    public init(
        title: String,
        start: Date,
        end: Date,
        joinURL: URL? = nil,
        notes: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.joinURL = joinURL
        self.notes = notes
    }

    public func encodedActionValue() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeActionValue(_ value: String?) -> Self? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }
}

public struct PersonalHubReminderDraft: Codable, Equatable, Sendable {
    public let title: String
    public let due: Date?
    public let calendarID: String?

    public init(title: String, due: Date? = nil, calendarID: String? = nil) {
        self.title = title
        self.due = due
        self.calendarID = calendarID
    }

    public func encodedActionValue() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeActionValue(_ value: String?) -> Self? {
        guard let value else { return nil }
        if let data = value.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(Self.self, from: data) { return decoded }
        }
        return .init(title: value)
    }
}

/// Conflict-safe note editor payload. A client edits the seed it received in a
/// snapshot and sends the base revision back; the Mac rejects a stale replace
/// instead of silently overwriting a newer edit from another device.
public struct PersonalHubNoteDraft: Codable, Equatable, Sendable {
    public let text: String
    public let category: String?
    public let baseRevision: Int?

    public init(text: String, category: String? = nil, baseRevision: Int? = nil) {
        self.text = text
        self.category = category
        self.baseRevision = baseRevision
    }

    public func encodedActionValue() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeActionValue(_ value: String?) -> Self? {
        guard let value else { return nil }
        if let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            return decoded
        }
        return .init(text: value)
    }
}

public struct PersonalHubChecklistMutation: Codable, Equatable, Sendable {
    public let lineIndex: Int
    public let baseRevision: Int

    public init(lineIndex: Int, baseRevision: Int) {
        self.lineIndex = lineIndex
        self.baseRevision = baseRevision
    }

    public func encodedActionValue() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decodeActionValue(_ value: String?) -> Self? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

public struct PersonalHubPrepareActionRequest: Codable, Equatable, Sendable {
    public let intent: PersonalHubActionIntent

    public init(intent: PersonalHubActionIntent) {
        self.intent = intent
    }
}

public struct PersonalHubPreparedAction: Codable, Equatable, Identifiable, Sendable {
    public let intent: PersonalHubActionIntent
    public let preview: String
    public let actionToken: String
    public let actionExpiresAt: Date

    public var id: String { intent.bindingID }

    public init(
        intent: PersonalHubActionIntent,
        preview: String,
        actionToken: String,
        actionExpiresAt: Date
    ) {
        self.intent = intent
        self.preview = preview
        self.actionToken = actionToken
        self.actionExpiresAt = actionExpiresAt
    }
}

public struct PersonalHubExecuteActionRequest: Codable, Equatable, Sendable {
    public let intent: PersonalHubActionIntent
    public let actionToken: String

    public init(intent: PersonalHubActionIntent, actionToken: String) {
        self.intent = intent
        self.actionToken = actionToken
    }
}

public struct PersonalHubActionResponse: Codable, Equatable, Sendable {
    public let executed: Bool
    public let message: String

    public init(executed: Bool, message: String) {
        self.executed = executed
        self.message = message
    }
}

public struct PersonalHubItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let detail: String?
    public let symbol: String?
    public let progress: Double?
    public let actions: [PersonalHubAction]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        progress: Double? = nil,
        actions: [PersonalHubAction] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.symbol = symbol
        self.progress = progress
        self.actions = actions
    }
}

public struct PersonalHubModuleSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: PersonalHubModuleID
    public let availability: PersonalHubAvailability
    public let summary: String
    public let detail: String?
    public let items: [PersonalHubItem]
    public let actions: [PersonalHubAction]

    public init(
        id: PersonalHubModuleID,
        availability: PersonalHubAvailability,
        summary: String,
        detail: String? = nil,
        items: [PersonalHubItem] = [],
        actions: [PersonalHubAction] = []
    ) {
        self.id = id
        self.availability = availability
        self.summary = summary
        self.detail = detail
        self.items = items
        self.actions = actions
    }
}

public struct PersonalHubSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let serverName: String
    public let generatedAt: Date
    public let requestedMode: PersonalHubMode
    public let resolvedMode: PersonalHubMode
    public let modules: [PersonalHubModuleSnapshot]

    public init(
        version: Int = 1,
        serverName: String,
        generatedAt: Date = Date(),
        requestedMode: PersonalHubMode,
        resolvedMode: PersonalHubMode,
        modules: [PersonalHubModuleSnapshot]
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.requestedMode = requestedMode
        self.resolvedMode = resolvedMode
        self.modules = modules
    }
}

public struct PersonalHubSnapshotRequest: Codable, Equatable, Sendable {
    public let requestedMode: PersonalHubMode

    public init(requestedMode: PersonalHubMode) {
        self.requestedMode = requestedMode
    }
}

public struct PersonalHubAutoContext: Equatable, Sendable {
    public var foregroundBundleID: String?
    public var minutesUntilMeeting: Int?
    public var agentNeedsAttention: Bool
    public var mediaIsPlaying: Bool

    public init(
        foregroundBundleID: String? = nil,
        minutesUntilMeeting: Int? = nil,
        agentNeedsAttention: Bool = false,
        mediaIsPlaying: Bool = false
    ) {
        self.foregroundBundleID = foregroundBundleID
        self.minutesUntilMeeting = minutesUntilMeeting
        self.agentNeedsAttention = agentNeedsAttention
        self.mediaIsPlaying = mediaIsPlaying
    }
}

public enum PersonalHubCatalog {
    public static let personalBaseline: [PersonalHubModuleID] = [
        .nowPlaying, .shelf, .calendar, .reminders, .notes,
        .system, .weather, .notifications, .claude, .agents, .github,
        .audio, .bluetooth, .battery, .quickToggles,
    ]

    public static let personalExtensions: [PersonalHubModuleID] = [
        .downloads, .camera, .teleprompter, .windowManager,
    ]

    public static let definitions: [PersonalHubModuleDefinition] = [
        .init(id: .nowPlaying, title: "Now Playing", symbol: "play.fill"),
        .init(id: .shelf, title: "Shelf", symbol: "tray.full.fill"),
        .init(id: .calendar, title: "Calendar", symbol: "calendar"),
        .init(id: .reminders, title: "Tasks", symbol: "checklist"),
        .init(id: .notes, title: "Notes", symbol: "note.text"),
        .init(id: .system, title: "System", symbol: "gauge.with.needle"),
        .init(id: .weather, title: "Weather", symbol: "cloud.sun.fill"),
        .init(id: .notifications, title: "Notifications", symbol: "bell.fill"),
        .init(id: .claude, title: "Claude", symbol: "sparkles"),
        .init(id: .agents, title: "Agents", symbol: "terminal.fill"),
        .init(id: .github, title: "GitHub", symbol: "point.3.connected.trianglepath.dotted"),
        .init(id: .audio, title: "Audio", symbol: "speaker.wave.2.fill"),
        .init(id: .bluetooth, title: "Bluetooth", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: .battery, title: "Battery", symbol: "battery.75percent"),
        .init(id: .quickToggles, title: "Quick Toggles", symbol: "switch.2"),
        .init(id: .downloads, title: "Downloads", symbol: "arrow.down.circle.fill"),
        .init(id: .camera, title: "Camera", symbol: "camera.fill"),
        .init(id: .teleprompter, title: "Prompter", symbol: "text.viewfinder"),
        .init(id: .windowManager, title: "Windows", symbol: "rectangle.3.group.fill"),
    ]

    public static func definition(for id: PersonalHubModuleID) -> PersonalHubModuleDefinition {
        definitions.first(where: { $0.id == id })
            ?? PersonalHubModuleDefinition(id: id, title: id.rawValue, symbol: "square.grid.2x2")
    }

    public static func modules(for mode: PersonalHubMode) -> [PersonalHubModuleID] {
        switch mode {
        case .auto:
            return modules(for: .home)
        case .home:
            return [.nowPlaying, .calendar, .weather, .quickToggles, .audio, .bluetooth, .battery]
        case .work:
            return [.calendar, .reminders, .notes, .teleprompter, .camera, .shelf, .notifications, .downloads]
        case .code:
            return [.agents, .github, .claude, .shelf, .system, .downloads, .windowManager]
        }
    }

    public static func resolvedMode(
        requested: PersonalHubMode,
        context: PersonalHubAutoContext
    ) -> PersonalHubMode {
        guard requested == .auto else { return requested }
        if context.agentNeedsAttention || isCodeApp(context.foregroundBundleID) {
            return .code
        }
        if let minutes = context.minutesUntilMeeting, (0...45).contains(minutes) {
            return .work
        }
        return .home
    }

    private static func isCodeApp(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID?.lowercased() else { return false }
        let fragments = [
            "xcode", "com.openai.codex", "com.anthropic.claudefordesktop",
            "visual-studio-code", "cursor", "warp", "terminal", "iterm",
        ]
        return fragments.contains(where: bundleID.contains)
    }
}
