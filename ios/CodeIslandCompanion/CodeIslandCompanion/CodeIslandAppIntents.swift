import AppIntents
import Foundation

enum CodeIslandIntentBridge {
    static let pendingRouteKey = "codeisland.intent.pendingRoute.v1"

    static func open(_ route: PersonalHubDeepLink) {
        UserDefaults.standard.set(route.url.absoluteString, forKey: pendingRouteKey)
        NotificationCenter.default.post(name: .codeIslandIntentRouteAvailable, object: nil)
    }
}

extension Notification.Name {
    static let codeIslandIntentRouteAvailable = Notification.Name("CodeIslandIntentRouteAvailable")
}

struct OpenPendingCodeIslandApprovalIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pending CodeIsland Approval"
    static var description = IntentDescription("Opens Buddy to the approval or decision that needs your attention.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.pendingApproval(id: nil))
        return .result()
    }
}

enum CodeIslandIntentModule: String, AppEnum {
    case nowPlaying, shelf, calendar, reminders, notes, system, weather, notifications
    case claude, agents, github, audio, bluetooth, battery, quickToggles
    case downloads, camera, teleprompter, windowManager

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "CodeIsland Module")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .nowPlaying: "Now Playing", .shelf: "Shelf", .calendar: "Calendar",
        .reminders: "Tasks", .notes: "Notes", .system: "System", .weather: "Weather",
        .notifications: "Notifications", .claude: "Claude", .agents: "Agents",
        .github: "GitHub", .audio: "Audio", .bluetooth: "Bluetooth", .battery: "Battery",
        .quickToggles: "Quick Toggles", .downloads: "Downloads", .camera: "Camera",
        .teleprompter: "Prompter", .windowManager: "Windows",
    ]
}

struct OpenCodeIslandModuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CodeIsland Module"
    static var description = IntentDescription("Opens a Buddy module over your private Tailscale connection.")
    static var openAppWhenRun = true

    @Parameter(title: "Module") var module: CodeIslandIntentModule

    func perform() async throws -> some IntentResult {
        guard let moduleID = PersonalHubModuleID(rawValue: module.rawValue) else { return .result() }
        CodeIslandIntentBridge.open(.module(moduleID))
        return .result()
    }
}

struct PrepareCodeIslandTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Prepare CodeIsland Task"
    static var description = IntentDescription("Opens a task draft for review before sending it to your paired computer.")
    static var openAppWhenRun = true

    @Parameter(title: "Task") var text: String?
    @Parameter(title: "Provider") var provider: CodeIslandIntentProvider?

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.newTask(text: text, provider: provider?.remoteProvider))
        return .result()
    }
}

enum CodeIslandIntentProvider: String, AppEnum {
    case automatic, codex, claude

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Coding Provider")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic",
        .codex: "Codex",
        .claude: "Claude",
    ]

    var remoteProvider: RemoteTaskProvider {
        switch self {
        case .automatic: return .auto
        case .codex: return .codex
        case .claude: return .claude
        }
    }
}

struct OpenCodeIslandTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CodeIsland Task"
    static var description = IntentDescription("Opens one exact coding task in Buddy.")
    static var openAppWhenRun = true

    @Parameter(title: "Task ID") var taskID: String

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        CodeIslandIntentBridge.open(.task(id: id))
        return .result()
    }
}

struct OpenCodeIslandNeedsYouIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CodeIsland Needs You"
    static var description = IntentDescription("Opens the decisions and coding tasks waiting for you.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.needsYou)
        return .result()
    }
}

struct OpenCodeIslandSessionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open CodeIsland Sessions"
    static var description = IntentDescription("Opens your active coding sessions and task portfolio.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.sessions)
        return .result()
    }
}

struct PrepareCodeIslandNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Prepare CodeIsland Note"
    static var description = IntentDescription("Opens a note draft for review before sending it to your paired computer.")
    static var openAppWhenRun = true

    @Parameter(title: "Note") var text: String?

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.quickJot(destination: .note, text: text))
        return .result()
    }
}

struct CodeIslandAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPendingCodeIslandApprovalIntent(),
            phrases: ["Open pending approval in \(.applicationName)"],
            shortTitle: "Pending Approval",
            systemImageName: "checkmark.shield.fill"
        )
        AppShortcut(
            intent: PrepareCodeIslandTaskIntent(),
            phrases: ["Prepare a task in \(.applicationName)"],
            shortTitle: "New Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: OpenCodeIslandNeedsYouIntent(),
            phrases: ["Open what needs me in \(.applicationName)"],
            shortTitle: "Needs You",
            systemImageName: "exclamationmark.bubble.fill"
        )
        AppShortcut(
            intent: OpenCodeIslandSessionsIntent(),
            phrases: ["Open sessions in \(.applicationName)"],
            shortTitle: "Sessions",
            systemImageName: "terminal.fill"
        )
        AppShortcut(
            intent: PrepareCodeIslandNoteIntent(),
            phrases: ["Prepare a note in \(.applicationName)"],
            shortTitle: "New Note",
            systemImageName: "note.text"
        )
    }
}
