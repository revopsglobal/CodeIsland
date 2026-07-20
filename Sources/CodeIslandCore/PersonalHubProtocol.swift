import Foundation

/// The four surfaces shared by the Mac notch, iPhone app, and private web app.
/// `auto` is a requested mode; snapshots always include the concrete resolved mode.
public enum PersonalHubMode: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
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
public enum PersonalHubModuleID: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
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

/// Exact Claude prompt and bounded text attachments included in the reviewed
/// action token. Legacy clients may still send a plain prompt with no files.
public struct PersonalHubClaudeContext: Codable, Equatable, Sendable {
    public let name: String
    public let text: String
    public let byteCount: Int
    public let wasTruncated: Bool

    public init(name: String, text: String, byteCount: Int, wasTruncated: Bool) {
        self.name = name
        self.text = text
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}

public enum PersonalHubClaudeContextError: LocalizedError, Equatable {
    case tooManyFiles
    case unsupportedType(String)
    case fileTooLarge(String)
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .tooManyFiles: return "Attach no more than \(PersonalHubClaudeContextPolicy.maximumFiles) text files"
        case .unsupportedType(let name): return "\(name) is not a supported text file"
        case .fileTooLarge(let name): return "\(name) is larger than 2 MB"
        case .unreadable(let name): return "\(name) is not readable UTF-8 text"
        }
    }
}

/// Shared limits for Mac, iPhone, web-originated payloads, and server-side
/// revalidation. Only bounded UTF-8 text crosses the remote action protocol.
public enum PersonalHubClaudeContextPolicy {
    public static let maximumFiles = 5
    public static let maximumFileBytes = 2_000_000
    public static let maximumCharactersPerFile = 12_000
    public static let maximumTotalCharacters = 20_000

    private static let allowedExtensions: Set<String> = [
        "txt", "md", "swift", "json", "yml", "yaml", "log", "csv", "ts", "tsx",
        "js", "jsx", "py", "sh", "zsh", "rb", "html", "css", "sql", "toml", "xml"
    ]

    public static func validate(namedData: [(String, Data)]) throws -> [PersonalHubClaudeContext] {
        guard namedData.count <= maximumFiles else { throw PersonalHubClaudeContextError.tooManyFiles }
        var remainingCharacters = maximumTotalCharacters
        return try namedData.map { name, data in
            let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { throw PersonalHubClaudeContextError.unsupportedType(name) }
            guard data.count <= maximumFileBytes else { throw PersonalHubClaudeContextError.fileTooLarge(name) }
            guard let rawText = String(data: data, encoding: .utf8) else {
                throw PersonalHubClaudeContextError.unreadable(name)
            }
            let allowedCount = min(maximumCharactersPerFile, remainingCharacters)
            let text = String(rawText.prefix(allowedCount))
            remainingCharacters = max(remainingCharacters - text.count, 0)
            return .init(
                name: String(name.prefix(240)),
                text: text,
                byteCount: data.count,
                wasTruncated: text.count < rawText.count
            )
        }
    }
}

public struct PersonalHubClaudeDraft: Codable, Equatable, Sendable {
    public let prompt: String
    public let contexts: [PersonalHubClaudeContext]

    public init(prompt: String, contexts: [PersonalHubClaudeContext] = []) {
        self.prompt = prompt
        self.contexts = contexts
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
        return .init(prompt: value)
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

public struct PersonalHubModeRack: Codable, Equatable, Sendable {
    public let mode: PersonalHubMode
    public let modules: [PersonalHubModuleID]

    public init(mode: PersonalHubMode, modules: [PersonalHubModuleID]) {
        self.mode = mode
        self.modules = modules
    }
}

public struct PersonalHubConfiguration: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let racks: [PersonalHubModeRack]
    public let dashboardEnabled: Bool
    /// Optional for backward compatibility with the first configuration files.
    /// Sanitization replaces it with the current catalog after migrations.
    public let knownModules: [PersonalHubModuleID]?

    public init(
        version: Int = currentVersion,
        racks: [PersonalHubModeRack],
        dashboardEnabled: Bool = true,
        knownModules: [PersonalHubModuleID]? = PersonalHubModuleID.allCases
    ) {
        self.version = version
        self.racks = racks
        self.dashboardEnabled = dashboardEnabled
        self.knownModules = knownModules
    }

    public static var `default`: Self {
        .init(
            racks: [.home, .work, .code].map {
                PersonalHubModeRack(mode: $0, modules: PersonalHubCatalog.modules(for: $0))
            }
        )
    }

    public static func sanitized(_ candidate: Self) -> Self {
        let previousKnown = Set(candidate.knownModules ?? [])
        let currentKnown = Set(PersonalHubModuleID.allCases)
        let introduced = currentKnown.subtracting(previousKnown)
        var rackByMode: [PersonalHubMode: [PersonalHubModuleID]] = [:]

        for mode in [PersonalHubMode.home, .work, .code] {
            let supplied = candidate.racks.first(where: { $0.mode == mode })?.modules
                ?? PersonalHubCatalog.modules(for: mode)
            var seen = Set<PersonalHubModuleID>()
            var modules = supplied.filter { currentKnown.contains($0) && seen.insert($0).inserted }
            for module in PersonalHubCatalog.modules(for: mode)
                where introduced.contains(module) && seen.insert(module).inserted {
                modules.append(module)
            }
            if modules.isEmpty {
                modules = PersonalHubCatalog.modules(for: mode)
            }
            rackByMode[mode] = modules
        }

        return .init(
            version: currentVersion,
            racks: [.home, .work, .code].map {
                PersonalHubModeRack(mode: $0, modules: rackByMode[$0] ?? [])
            },
            dashboardEnabled: candidate.dashboardEnabled,
            knownModules: PersonalHubModuleID.allCases
        )
    }

    public func rack(for mode: PersonalHubMode) -> [PersonalHubModuleID] {
        let concreteMode = mode == .auto ? PersonalHubMode.home : mode
        return racks.first(where: { $0.mode == concreteMode })?.modules
            ?? PersonalHubCatalog.modules(for: concreteMode)
    }

    public static func dayProgress(
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / duration, 0), 1)
    }
}

public struct PersonalHubConfigurationMutation: Codable, Equatable, Sendable {
    public let mode: PersonalHubMode?
    public let modules: [PersonalHubModuleID]?
    public let dashboardEnabled: Bool?

    public init(
        mode: PersonalHubMode? = nil,
        modules: [PersonalHubModuleID]? = nil,
        dashboardEnabled: Bool? = nil
    ) {
        self.mode = mode
        self.modules = modules
        self.dashboardEnabled = dashboardEnabled
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
    /// Small, bounded artwork encoded as a data URL so the authenticated
    /// snapshot renders identically on Mac, iPhone, and the private web app.
    public let artworkDataURL: String?
    /// Absolute playback values allow clients to render and submit an
    /// arbitrary seek without inferring duration from a rounded progress bar.
    public let mediaPosition: Double?
    public let mediaDuration: Double?
    /// Optional semantic date used by calendar-style clients. Existing module
    /// items remain date-free and legacy payloads decode this as nil.
    public let date: Date?
    public let actions: [PersonalHubAction]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        symbol: String? = nil,
        progress: Double? = nil,
        artworkDataURL: String? = nil,
        mediaPosition: Double? = nil,
        mediaDuration: Double? = nil,
        date: Date? = nil,
        actions: [PersonalHubAction] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.symbol = symbol
        self.progress = progress
        self.artworkDataURL = artworkDataURL
        self.mediaPosition = mediaPosition
        self.mediaDuration = mediaDuration
        self.date = date
        self.actions = actions
    }
}

public extension PersonalHubItem {
    /// Only accepts the bounded JPEG data URL emitted by the Mac. Clients do
    /// not load remote artwork URLs, preserving tailnet-only snapshot privacy.
    var decodedArtworkJPEG: Data? {
        let prefix = "data:image/jpeg;base64,"
        guard let artworkDataURL,
              artworkDataURL.hasPrefix(prefix),
              let data = Data(base64Encoded: String(artworkDataURL.dropFirst(prefix.count))),
              data.count <= 300_000,
              data.starts(with: [0xFF, 0xD8]) else {
            return nil
        }
        return data
    }
}

public struct PersonalHubCalendarDay: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let date: Date
    public let isInDisplayedMonth: Bool
    public let isToday: Bool
    public let eventCount: Int

    public init(
        id: String,
        date: Date,
        isInDisplayedMonth: Bool,
        isToday: Bool,
        eventCount: Int
    ) {
        self.id = id
        self.date = date
        self.isInDisplayedMonth = isInDisplayedMonth
        self.isToday = isToday
        self.eventCount = eventCount
    }
}

/// A fixed six-week month grid generated in the Mac's local Calendar. Dates
/// are semantic values; each client formats them for presentation without
/// reconstructing month boundaries in a potentially different time zone.
public struct PersonalHubCalendarMonth: Codable, Equatable, Sendable {
    public let displayedMonth: Date
    public let selectedDate: Date
    public let days: [PersonalHubCalendarDay]
    public let selectedEvents: [PersonalHubItem]

    public init(
        displayedMonth: Date,
        selectedDate: Date,
        days: [PersonalHubCalendarDay],
        selectedEvents: [PersonalHubItem] = []
    ) {
        self.displayedMonth = displayedMonth
        self.selectedDate = selectedDate
        self.days = days
        self.selectedEvents = selectedEvents
    }

    public static func make(
        referenceDate: Date,
        selectedDate: Date,
        eventDates: [Date],
        selectedEvents: [PersonalHubItem] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let monthStart = calendar.dateInterval(of: .month, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart)
            ?? monthStart
        let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart)
            ?? gridStart.addingTimeInterval(42 * 86_400)
        let requestedSelection = calendar.startOfDay(for: selectedDate)
        let normalizedSelection = (requestedSelection >= gridStart && requestedSelection < gridEnd)
            ? requestedSelection
            : monthStart

        var eventCounts: [Date: Int] = [:]
        for date in eventDates {
            eventCounts[calendar.startOfDay(for: date), default: 0] += 1
        }

        let displayedComponents = calendar.dateComponents([.era, .year, .month], from: monthStart)
        let days = (0..<42).compactMap { offset -> PersonalHubCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let start = calendar.startOfDay(for: date)
            let components = calendar.dateComponents([.era, .year, .month, .day], from: start)
            let identifier = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            let monthComponents = calendar.dateComponents([.era, .year, .month], from: start)
            return PersonalHubCalendarDay(
                id: identifier,
                date: start,
                isInDisplayedMonth: monthComponents == displayedComponents,
                isToday: calendar.isDate(start, inSameDayAs: now),
                eventCount: eventCounts[start, default: 0]
            )
        }

        return .init(
            displayedMonth: monthStart,
            selectedDate: normalizedSelection,
            days: days,
            selectedEvents: selectedEvents
        )
    }
}

public struct PersonalHubModuleSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: PersonalHubModuleID
    public let availability: PersonalHubAvailability
    public let summary: String
    public let detail: String?
    public let items: [PersonalHubItem]
    public let actions: [PersonalHubAction]
    public let calendarMonth: PersonalHubCalendarMonth?

    public init(
        id: PersonalHubModuleID,
        availability: PersonalHubAvailability,
        summary: String,
        detail: String? = nil,
        items: [PersonalHubItem] = [],
        actions: [PersonalHubAction] = [],
        calendarMonth: PersonalHubCalendarMonth? = nil
    ) {
        self.id = id
        self.availability = availability
        self.summary = summary
        self.detail = detail
        self.items = items
        self.actions = actions
        self.calendarMonth = calendarMonth
    }
}

public struct PersonalHubSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let serverName: String
    public let generatedAt: Date
    public let requestedMode: PersonalHubMode
    public let resolvedMode: PersonalHubMode
    public let modules: [PersonalHubModuleSnapshot]
    public let configuration: PersonalHubConfiguration?
    public let dayProgress: Double?

    public init(
        version: Int = 1,
        serverName: String,
        generatedAt: Date = Date(),
        requestedMode: PersonalHubMode,
        resolvedMode: PersonalHubMode,
        modules: [PersonalHubModuleSnapshot],
        configuration: PersonalHubConfiguration? = nil,
        dayProgress: Double? = nil
    ) {
        self.version = version
        self.serverName = serverName
        self.generatedAt = generatedAt
        self.requestedMode = requestedMode
        self.resolvedMode = resolvedMode
        self.modules = modules
        self.configuration = configuration
        self.dayProgress = dayProgress
    }
}

public struct PersonalHubSnapshotRequest: Codable, Equatable, Sendable {
    public let requestedMode: PersonalHubMode
    public let calendarReferenceDate: Date?
    public let calendarSelectedDate: Date?

    public init(
        requestedMode: PersonalHubMode,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil
    ) {
        self.requestedMode = requestedMode
        self.calendarReferenceDate = calendarReferenceDate
        self.calendarSelectedDate = calendarSelectedDate
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

    public static func preferredMode(for id: PersonalHubModuleID) -> PersonalHubMode {
        if modules(for: .code).contains(id) { return .code }
        if modules(for: .work).contains(id) { return .work }
        return .home
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

public enum PersonalHubQuickJotDestination: String, Codable, CaseIterable, Sendable {
    case task
    case note
}

public enum PersonalHubDeepLink: Equatable, Sendable {
    case pendingApproval(id: String?)
    case pendingQuestion(id: String?)
    case module(PersonalHubModuleID)
    case quickJot(destination: PersonalHubQuickJotDestination, text: String?)
    case task(id: UUID)
    case newTask(text: String?, provider: RemoteTaskProvider? = nil)
    case needsYou
    case sessions

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "codeisland",
              let host = url.host?.lowercased()
        else { return nil }
        let path = Array(url.pathComponents.dropFirst())
        switch host {
        case "approval", "approvals":
            let rawID = path.first
            self = .pendingApproval(id: rawID == "pending" ? nil : rawID)
        case "question", "questions":
            let rawID = path.first
            self = .pendingQuestion(id: rawID == "pending" ? nil : rawID)
        case "hub":
            guard let raw = path.first, let module = PersonalHubModuleID(rawValue: raw) else { return nil }
            self = .module(module)
        case "quick-jot":
            guard let raw = path.first,
                  let destination = PersonalHubQuickJotDestination(rawValue: raw.lowercased())
            else { return nil }
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "text" })?.value
            self = .quickJot(destination: destination, text: text)
        case "tasks":
            guard let rawID = path.first, let id = UUID(uuidString: rawID) else { return nil }
            self = .task(id: id)
        case "new-task":
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            let text = queryItems?.first(where: { $0.name == "text" })?.value
            let provider = queryItems?
                .first(where: { $0.name == "provider" })?
                .value
                .flatMap(RemoteTaskProvider.init(rawValue:))
            self = .newTask(text: text, provider: provider)
        case "needs-you":
            guard path.isEmpty else { return nil }
            self = .needsYou
        case "sessions":
            guard path.isEmpty else { return nil }
            self = .sessions
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "codeisland"
        switch self {
        case .pendingApproval(let id):
            components.host = "approvals"
            components.path = "/\(id ?? "pending")"
        case .pendingQuestion(let id):
            components.host = "questions"
            components.path = "/\(id ?? "pending")"
        case .module(let module):
            components.host = "hub"
            components.path = "/\(module.rawValue)"
        case .quickJot(let destination, let text):
            components.host = "quick-jot"
            components.path = "/\(destination.rawValue)"
            if let text, !text.isEmpty {
                components.queryItems = [URLQueryItem(name: "text", value: text)]
            }
        case .task(let id):
            components.host = "tasks"
            components.path = "/\(id.uuidString)"
        case .newTask(let text, let provider):
            components.host = "new-task"
            var items: [URLQueryItem] = []
            if let text, !text.isEmpty {
                items.append(URLQueryItem(name: "text", value: text))
            }
            if let provider { items.append(URLQueryItem(name: "provider", value: provider.rawValue)) }
            components.queryItems = items.isEmpty ? nil : items
        case .needsYou:
            components.host = "needs-you"
        case .sessions:
            components.host = "sessions"
        }
        return components.url!
    }
}

public enum PersonalHubBuddyActionDisposition: Equatable, Sendable {
    case native
    case readOnly
    case macOnly(reason: String)
}

public struct PersonalHubBuddyRoute: Equatable, Sendable {
    public let moduleID: PersonalHubModuleID
    public let actionDispositions: [String: PersonalHubBuddyActionDisposition]

    public init(
        moduleID: PersonalHubModuleID,
        actionDispositions: [String: PersonalHubBuddyActionDisposition]
    ) {
        self.moduleID = moduleID
        self.actionDispositions = actionDispositions
    }
}

public struct PersonalHubBuddyParityViolation: Equatable, CustomStringConvertible, Sendable {
    public let moduleID: PersonalHubModuleID
    public let actionID: String
    public let location: String
    public let reason: String

    public init(
        moduleID: PersonalHubModuleID,
        actionID: String,
        location: String,
        reason: String
    ) {
        self.moduleID = moduleID
        self.actionID = actionID
        self.location = location
        self.reason = reason
    }

    public var description: String {
        "\(moduleID.rawValue).\(actionID) at \(location): \(reason)"
    }
}

public enum PersonalHubBuddyParity {
    public static let routes: [PersonalHubBuddyRoute] = [
        .init(moduleID: .nowPlaying, actionDispositions: native("previous", "playPause", "playQueueItem", "next", "seek", "seekBack", "seekForward", "copyToDevice")),
        .init(moduleID: .shelf, actionDispositions: native("downloadToDevice", "copyToDevice", "remove").merging(macOnly("revealOnMac", reason: "Reveals the source file in Finder on the Mac"), uniquingKeysWith: { first, _ in first })),
        .init(moduleID: .calendar, actionDispositions: native("add", "edit", "delete", "join", "openOnMac")),
        .init(moduleID: .reminders, actionDispositions: native("add", "addList", "deleteList", "complete", "restore", "delete", "moveUp", "moveTop", "moveDown", "copyToDevice")),
        .init(moduleID: .notes, actionDispositions: native("add", "delete", "append", "replace", "setCategory", "undo", "toggleChecklist", "copyToDevice")),
        .init(moduleID: .system, actionDispositions: readOnly("refresh")),
        .init(moduleID: .weather, actionDispositions: readOnly("refresh")),
        .init(moduleID: .notifications, actionDispositions: ["view": .readOnly]),
        .init(moduleID: .claude, actionDispositions: native("ask", "plan", "applyProposal", "copyToDevice")),
        .init(moduleID: .agents, actionDispositions: readOnly("refresh", "view")),
        .init(moduleID: .github, actionDispositions: native("open").merging(readOnly("refresh"), uniquingKeysWith: { first, _ in first })),
        .init(moduleID: .audio, actionDispositions: native("volumeDown", "setVolume", "volumeUp", "setInput", "setOutput", "openSettings")),
        .init(moduleID: .bluetooth, actionDispositions: native("refresh", "connect", "disconnect")),
        .init(moduleID: .battery, actionDispositions: readOnly("refresh", "view")),
        .init(moduleID: .quickToggles, actionDispositions: native("darkMode", "mute", "displaySleep", "lockMac", "setModeRack", "setDashboard")),
        .init(moduleID: .downloads, actionDispositions: native("refresh", "downloadToDevice").merging(macOnly("reveal", reason: "Reveals the download in Finder on the Mac"), uniquingKeysWith: { first, _ in first })),
        .init(moduleID: .camera, actionDispositions: native("previewLocal")),
        .init(moduleID: .teleprompter, actionDispositions: native("set", "presentOnDevice", "copyToDevice")),
        .init(moduleID: .windowManager, actionDispositions: native("left", "maximize", "right").merging(macOnly("openAccessibility", reason: "Accessibility permission must be granted in Mac System Settings"), uniquingKeysWith: { first, _ in first })),
    ]

    public static func route(for moduleID: PersonalHubModuleID) -> PersonalHubBuddyRoute? {
        routes.first(where: { $0.moduleID == moduleID })
    }

    public static func disposition(
        for moduleID: PersonalHubModuleID,
        actionID: String
    ) -> PersonalHubBuddyActionDisposition? {
        route(for: moduleID)?.actionDispositions[actionID]
    }

    public static func isReadOnlyAction(
        moduleID: PersonalHubModuleID,
        actionID: String
    ) -> Bool {
        disposition(for: moduleID, actionID: actionID) == .readOnly
    }

    public static func validate(snapshot: PersonalHubSnapshot) -> [PersonalHubBuddyParityViolation] {
        snapshot.modules.flatMap(validate(module:))
    }

    public static func validate(module: PersonalHubModuleSnapshot) -> [PersonalHubBuddyParityViolation] {
        guard let route = route(for: module.id) else {
            return allActions(in: module).map {
                PersonalHubBuddyParityViolation(
                    moduleID: module.id,
                    actionID: $0.id,
                    location: $0.location,
                    reason: "missing Buddy route"
                )
            }
        }

        return allActions(in: module).compactMap { entry in
            guard let disposition = route.actionDispositions[entry.id] else {
                return PersonalHubBuddyParityViolation(
                    moduleID: module.id,
                    actionID: entry.id,
                    location: entry.location,
                    reason: "missing Buddy action disposition"
                )
            }
            if case .macOnly(let reason) = disposition,
               reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return PersonalHubBuddyParityViolation(
                    moduleID: module.id,
                    actionID: entry.id,
                    location: entry.location,
                    reason: "Mac-only action is missing a reason"
                )
            }
            return nil
        }
    }

    private static func native(_ ids: String...) -> [String: PersonalHubBuddyActionDisposition] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, .native) })
    }

    private static func readOnly(_ ids: String...) -> [String: PersonalHubBuddyActionDisposition] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, .readOnly) })
    }

    private static func macOnly(
        _ id: String,
        reason: String
    ) -> [String: PersonalHubBuddyActionDisposition] {
        [id: .macOnly(reason: reason)]
    }

    private struct ActionEntry {
        let id: String
        let location: String
    }

    private static func allActions(in module: PersonalHubModuleSnapshot) -> [ActionEntry] {
        var entries = module.actions.map { ActionEntry(id: $0.id, location: "module.actions") }
        for item in module.items {
            entries.append(contentsOf: item.actions.map {
                ActionEntry(id: $0.id, location: "items[\(item.id)].actions")
            })
        }
        if let calendarMonth = module.calendarMonth {
            for item in calendarMonth.selectedEvents {
                entries.append(contentsOf: item.actions.map {
                    ActionEntry(id: $0.id, location: "calendarMonth.selectedEvents[\(item.id)].actions")
                })
            }
        }
        return entries
    }
}
