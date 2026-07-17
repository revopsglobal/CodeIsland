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
    static var description = IntentDescription("Opens a Mac-backed Buddy module over your private Tailscale connection.")
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
    static var description = IntentDescription("Opens a task draft. You review it before Buddy sends it to your Mac.")
    static var openAppWhenRun = true

    @Parameter(title: "Task") var text: String?

    func perform() async throws -> some IntentResult {
        CodeIslandIntentBridge.open(.quickJot(destination: .task, text: text))
        return .result()
    }
}

struct PrepareCodeIslandNoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Prepare CodeIsland Note"
    static var description = IntentDescription("Opens a note draft. You review it before Buddy sends it to your Mac.")
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
            intent: PrepareCodeIslandNoteIntent(),
            phrases: ["Prepare a note in \(.applicationName)"],
            shortTitle: "New Note",
            systemImageName: "note.text"
        )
    }
}
