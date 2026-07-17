import AppKit
import Foundation
import CodeIslandCore

/// Builds the shared Mac/iPhone/web hub snapshot and executes the deliberately
/// small set of remote mutations that are implemented today. Adding a module to
/// the catalog does not automatically grant it a remote action.
@MainActor
final class PersonalHubService {
    static let shared = PersonalHubService()

    enum ActionError: LocalizedError, Equatable {
        case invalid(String)
        case unsupported
        case expired
        case unauthorized
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message): return message
            case .unsupported: return "This action is not available yet"
            case .expired: return "Action confirmation expired; review it again"
            case .unauthorized: return "Action confirmation is invalid"
            case .failed(let message): return message
            }
        }
    }

    private var actionTokens = RemoteActionTokenVault()
    private let glances = GlancesModel.shared
    private let utilities = PersonalUtilitiesModel.shared
    private let data = PersonalHubDataModel.shared

    private init() {}

    func snapshot(
        appState: AppState,
        requestedMode: PersonalHubMode,
        serverName: String = Host.current().localizedName ?? "CodeIsland Mac"
    ) -> PersonalHubSnapshot {
        glances.refresh()
        utilities.start()
        data.start()

        let minutesUntilMeeting = glances.nextEvent.map {
            Int($0.start.timeIntervalSinceNow / 60)
        }
        let context = PersonalHubAutoContext(
            foregroundBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            minutesUntilMeeting: minutesUntilMeeting,
            agentNeedsAttention: !appState.permissionQueue.isEmpty || !appState.questionQueue.isEmpty,
            mediaIsPlaying: false
        )
        let resolvedMode = PersonalHubCatalog.resolvedMode(requested: requestedMode, context: context)
        let moduleIDs = PersonalHubCatalog.modules(for: resolvedMode)

        return PersonalHubSnapshot(
            serverName: serverName,
            requestedMode: requestedMode,
            resolvedMode: resolvedMode,
            modules: moduleIDs.map { moduleSnapshot(id: $0, appState: appState) }
        )
    }

    func prepare(
        intent: PersonalHubActionIntent,
        deviceID: String
    ) -> Result<PersonalHubPreparedAction, ActionError> {
        switch validate(intent: intent) {
        case .failure(let error):
            return .failure(error)
        case .success(let preview):
            let token = actionTokens.issue(requestID: intent.bindingID, deviceID: deviceID)
            return .success(PersonalHubPreparedAction(
                intent: intent,
                preview: preview,
                actionToken: token.rawValue,
                actionExpiresAt: token.expiresAt
            ))
        }
    }

    func execute(
        request: PersonalHubExecuteActionRequest,
        deviceID: String
    ) -> Result<PersonalHubActionResponse, ActionError> {
        switch actionTokens.consume(
            requestID: request.intent.bindingID,
            deviceID: deviceID,
            token: request.actionToken
        ) {
        case .expired:
            return .failure(.expired)
        case .invalid:
            return .failure(.unauthorized)
        case .accepted:
            break
        }

        switch validate(intent: request.intent) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        let intent = request.intent
        switch (intent.moduleID, intent.actionID) {
        case (.notes, "add"):
            guard let value = intent.value, data.addNote(value) else {
                return .failure(.failed("Could not add the note"))
            }
            return .success(.init(executed: true, message: "Note added"))

        case (.notes, "delete"):
            guard let targetID = intent.targetID, data.deleteNote(id: targetID) else {
                return .failure(.invalid("Note is no longer available"))
            }
            return .success(.init(executed: true, message: "Note deleted"))

        case (.notes, "replace"):
            guard let targetID = intent.targetID,
                  let value = intent.value,
                  data.replaceNote(id: targetID, rawText: value) else {
                return .failure(.invalid("Note is no longer available"))
            }
            return .success(.init(executed: true, message: "Note updated"))

        case (.notes, "append"):
            guard let targetID = intent.targetID,
                  let value = intent.value,
                  data.appendToNote(id: targetID, rawText: value) else {
                return .failure(.invalid("Note is no longer available"))
            }
            return .success(.init(executed: true, message: "Text appended to note"))

        case (.teleprompter, "set"):
            guard let value = intent.value, data.setTeleprompterText(value) else {
                return .failure(.failed("Could not save the teleprompter script"))
            }
            return .success(.init(executed: true, message: "Teleprompter script saved"))

        case (.claude, "ask"):
            guard let value = intent.value, data.askClaude(value) else {
                return .failure(.failed(data.claudeError ?? "Claude is already answering another question"))
            }
            return .success(.init(executed: true, message: "Question sent to Claude on the Mac"))

        case (.shelf, "remove"):
            guard let targetID = intent.targetID, data.removeShelfEntry(id: targetID) else {
                return .failure(.invalid("Shelf item is no longer available"))
            }
            return .success(.init(executed: true, message: "Shelf item removed"))

        case (.nowPlaying, "playPause"), (.nowPlaying, "next"), (.nowPlaying, "previous"):
            guard data.runMediaCommand(intent.actionID) else {
                return .failure(.failed("Could not control the current media app"))
            }
            return .success(.init(executed: true, message: "Media control sent"))

        case (.system, "refresh"):
            data.refreshHostData()
            return .success(.init(executed: true, message: "System readings refreshed"))

        case (.audio, "openSettings"):
            guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else {
                return .failure(.failed("Sound Settings is unavailable"))
            }
            NSWorkspace.shared.open(url)
            return .success(.init(executed: true, message: "Sound Settings opened on the Mac"))

        case (.audio, "setInput"), (.audio, "setOutput"):
            guard let targetID = intent.targetID else {
                return .failure(.invalid("Audio device is no longer available"))
            }
            let role: AudioDeviceController.Role = intent.actionID == "setInput" ? .input : .output
            guard AudioDeviceController.setDefaultDevice(named: targetID, role: role) else {
                return .failure(.failed("Could not switch the Mac audio device"))
            }
            data.refreshHostData()
            return .success(.init(
                executed: true,
                message: "Default \(intent.actionID == "setInput" ? "input" : "output") set to \(targetID)"
            ))

        case (.quickToggles, "lockMac"):
            let script = #"tell application "System Events" to keystroke "q" using {control down, command down}"#
            guard ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 5) != nil else {
                return .failure(.failed("CodeIsland needs Accessibility access to lock the Mac"))
            }
            return .success(.init(executed: true, message: "Mac locked"))

        case (.quickToggles, "darkMode"):
            guard data.toggleDarkMode() else {
                return .failure(.failed("Allow CodeIsland to control System Events in Privacy & Security → Automation"))
            }
            return .success(.init(executed: true, message: "Appearance toggled"))

        case (.quickToggles, "mute"):
            guard data.toggleMute() else {
                return .failure(.failed("Could not change Mac audio mute"))
            }
            return .success(.init(executed: true, message: "Mac audio mute toggled"))

        case (.quickToggles, "displaySleep"):
            guard ProcessRunner.run(path: "/usr/bin/pmset", args: ["displaysleepnow"], timeout: 5) != nil else {
                return .failure(.failed("Could not sleep the Mac display"))
            }
            return .success(.init(executed: true, message: "Mac display put to sleep"))

        case (.windowManager, "openAccessibility"):
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                return .failure(.failed("Accessibility Settings is unavailable"))
            }
            NSWorkspace.shared.open(url)
            return .success(.init(executed: true, message: "Accessibility Settings opened on the Mac"))

        case (.windowManager, "left"), (.windowManager, "right"), (.windowManager, "maximize"):
            let placement: WindowManagerController.Placement
            switch intent.actionID {
            case "left": placement = .left
            case "right": placement = .right
            default: placement = .maximize
            }
            guard WindowManagerController.placeFrontWindow(placement) else {
                return .failure(.failed("Grant CodeIsland Accessibility access and keep a normal app window frontmost"))
            }
            return .success(.init(executed: true, message: "Front window moved"))

        case (.reminders, "add"):
            guard let draft = PersonalHubReminderDraft.decodeActionValue(intent.value),
                  glances.addReminder(title: draft.title, due: draft.due) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not add the task"))
            }
            return .success(.init(executed: true, message: "Task added"))

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            glances.complete(reminder)
            return .success(.init(executed: true, message: "Task completed"))

        case (.reminders, "delete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            guard glances.deleteReminder(reminder) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not delete the task"))
            }
            return .success(.init(executed: true, message: "Task deleted"))

        case (.calendar, "add"):
            guard let draft = PersonalHubCalendarDraft.decodeActionValue(intent.value),
                  glances.addEvent(draft) else {
                return .failure(.failed(glances.calendarMutationError ?? "Could not add the event"))
            }
            return .success(.init(executed: true, message: "Event added"))

        case (.calendar, "delete"):
            guard let targetID = intent.targetID, glances.deleteEvent(id: targetID) else {
                return .failure(.failed(glances.calendarMutationError ?? "Could not delete the event"))
            }
            return .success(.init(executed: true, message: "Event deleted"))

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID }),
                  let joinURL = event.joinURL
            else { return .failure(.invalid("Meeting link is no longer available")) }
            NSWorkspace.shared.open(joinURL)
            return .success(.init(executed: true, message: "Meeting opened on the Mac"))

        case (.downloads, "reveal"):
            guard let targetID = intent.targetID,
                  let download = utilities.downloads.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Download is no longer available")) }
            NSWorkspace.shared.activateFileViewerSelecting([download.url])
            return .success(.init(executed: true, message: "Download revealed on the Mac"))

        case (.bluetooth, "refresh"):
            utilities.refreshBluetooth(force: true)
            return .success(.init(executed: true, message: "Bluetooth devices refreshed"))

        case (.bluetooth, "connect"), (.bluetooth, "disconnect"):
            guard let targetID = intent.targetID else {
                return .failure(.invalid("Bluetooth device is no longer available"))
            }
            let succeeded = intent.actionID == "connect"
                ? BluetoothDeviceController.connect(address: targetID)
                : BluetoothDeviceController.disconnect(address: targetID)
            guard succeeded else {
                return .failure(.failed("Could not \(intent.actionID) the Bluetooth device"))
            }
            utilities.refreshBluetooth(force: true)
            return .success(.init(executed: true, message: "Bluetooth \(intent.actionID) request completed"))

        case (.weather, "refresh"):
            glances.refreshWeather()
            return .success(.init(executed: true, message: "Weather refreshed"))

        default:
            return .failure(.unsupported)
        }
    }

    private func validate(intent: PersonalHubActionIntent) -> Result<String, ActionError> {
        switch (intent.moduleID, intent.actionID) {
        case (.notes, "add"):
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return .failure(.invalid("Enter a note")) }
            guard value.count <= 20_000 else { return .failure(.invalid("Note is too long")) }
            return .success("Add note: “\(value.prefix(120))\(value.count > 120 ? "…" : "")”")

        case (.notes, "delete"):
            guard let targetID = intent.targetID,
                  let note = data.notes.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Note is no longer available")) }
            return .success("Delete note “\(note.title)”")

        case (.notes, "replace"), (.notes, "append"):
            guard let targetID = intent.targetID,
                  let note = data.notes.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Note is no longer available")) }
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return .failure(.invalid("Enter note text")) }
            let limit = intent.actionID == "append" ? max(20_000 - note.text.count - 1, 0) : 20_000
            guard value.count <= limit else { return .failure(.invalid("Note is too long")) }
            return .success(intent.actionID == "append"
                ? "Append text to “\(note.title)”"
                : "Replace the contents of “\(note.title)”")

        case (.teleprompter, "set"):
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return .failure(.invalid("Enter a teleprompter script")) }
            guard value.count <= 50_000 else { return .failure(.invalid("Script is too long")) }
            return .success("Replace the teleprompter script with \(value.count) characters")

        case (.claude, "ask"):
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !data.claudeBusy else { return .failure(.invalid("Claude is already answering")) }
            guard !value.isEmpty else { return .failure(.invalid("Enter a question")) }
            guard value.count <= 20_000 else { return .failure(.invalid("Question is too long")) }
            return .success("Ask Claude: “\(value.prefix(160))\(value.count > 160 ? "…" : "")”")

        case (.shelf, "remove"):
            guard let targetID = intent.targetID,
                  let entry = data.shelf.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Shelf item is no longer available")) }
            return .success("Remove “\(entry.title)” from Shelf")

        case (.nowPlaying, "playPause"):
            guard let media = data.nowPlaying else { return .failure(.invalid("Nothing is playing")) }
            return .success("\(media.isPlaying ? "Pause" : "Play") “\(media.title)”")

        case (.nowPlaying, "next"):
            guard data.nowPlaying != nil else { return .failure(.invalid("Nothing is playing")) }
            return .success("Skip to the next track")

        case (.nowPlaying, "previous"):
            guard data.nowPlaying != nil else { return .failure(.invalid("Nothing is playing")) }
            return .success("Return to the previous track")

        case (.system, "refresh"):
            return .success("Refresh system readings")

        case (.audio, "openSettings"):
            return .success("Open Sound Settings on the Mac")

        case (.audio, "setInput"), (.audio, "setOutput"):
            guard let targetID = intent.targetID,
                  let device = data.audioDevices.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Audio device is no longer available")) }
            let input = intent.actionID == "setInput"
            guard input ? device.isInput : device.isOutput else {
                return .failure(.invalid("That device does not support the selected audio role"))
            }
            return .success("Set “\(device.name)” as the Mac's default \(input ? "input" : "output")")

        case (.quickToggles, "lockMac"):
            return .success("Lock this Mac now")

        case (.quickToggles, "darkMode"):
            return .success("Switch this Mac to \(data.quickSettings?.darkMode == true ? "Light" : "Dark") Mode")

        case (.quickToggles, "mute"):
            return .success("\(data.quickSettings?.outputMuted == true ? "Unmute" : "Mute") Mac audio")

        case (.quickToggles, "displaySleep"):
            return .success("Turn off this Mac's display now")

        case (.windowManager, "openAccessibility"):
            return .success("Open Accessibility Settings on the Mac")

        case (.windowManager, "left"), (.windowManager, "right"), (.windowManager, "maximize"):
            guard WindowManagerController.isAuthorized else {
                return .failure(.invalid("Accessibility access is required on the Mac"))
            }
            let label: String
            switch intent.actionID {
            case "left": label = "left half"
            case "right": label = "right half"
            default: label = "full screen area"
            }
            return .success("Move the Mac's front window to the \(label)")

        case (.reminders, "add"):
            guard let draft = PersonalHubReminderDraft.decodeActionValue(intent.value) else {
                return .failure(.invalid("Enter a task"))
            }
            let value = GlancesModel.normalizedReminderTitle(draft.title)
            guard glances.remindersAuthorized else {
                return .failure(.invalid("Reminders access is required on the Mac"))
            }
            guard !value.isEmpty else { return .failure(.invalid("Enter a task")) }
            guard value.count <= 500 else { return .failure(.invalid("Task is too long")) }
            let due = draft.due.map { " due \(Self.actionDate($0))" } ?? ""
            return .success("Add “\(value)” to the selected Reminders list\(due)")

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            return .success("Mark “\(reminder.title)” complete")

        case (.reminders, "delete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            return .success("Delete task “\(reminder.title)”")

        case (.calendar, "add"):
            guard glances.calendarAuthorized else {
                return .failure(.invalid("Calendar access is required on the Mac"))
            }
            guard let draft = PersonalHubCalendarDraft.decodeActionValue(intent.value) else {
                return .failure(.invalid("Enter an event title and time"))
            }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .failure(.invalid("Enter an event title")) }
            guard title.count <= 500 else { return .failure(.invalid("Event title is too long")) }
            guard draft.end > draft.start else { return .failure(.invalid("Event end must be after its start")) }
            guard draft.start > Date().addingTimeInterval(-300) else {
                return .failure(.invalid("Choose a future event time"))
            }
            if let url = draft.joinURL, !GlancesModel.isTrustedJoinURL(url) {
                return .failure(.invalid("Use a supported HTTPS meeting link"))
            }
            return .success("Add “\(title)” on \(Self.actionDate(draft.start))")

        case (.calendar, "delete"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Event is no longer available")) }
            return .success("Delete event “\(event.title)”")

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID }),
                  event.joinURL != nil
            else { return .failure(.invalid("Meeting link is no longer available")) }
            return .success("Open “\(event.title)” on the Mac")

        case (.downloads, "reveal"):
            guard let targetID = intent.targetID,
                  let download = utilities.downloads.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Download is no longer available")) }
            return .success("Reveal “\(download.name)” on the Mac")

        case (.bluetooth, "refresh"):
            return .success("Refresh Bluetooth devices")

        case (.bluetooth, "connect"), (.bluetooth, "disconnect"):
            guard let targetID = intent.targetID,
                  let device = utilities.bluetoothDevices.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Bluetooth device is no longer available")) }
            if intent.actionID == "connect", device.isConnected {
                return .failure(.invalid("\(device.name) is already connected"))
            }
            if intent.actionID == "disconnect", !device.isConnected {
                return .failure(.invalid("\(device.name) is already disconnected"))
            }
            return .success("\(intent.actionID.capitalized) “\(device.name)”")

        case (.weather, "refresh"):
            return .success("Refresh weather")

        default:
            return .failure(.unsupported)
        }
    }

    private func moduleSnapshot(
        id: PersonalHubModuleID,
        appState: AppState
    ) -> PersonalHubModuleSnapshot {
        switch id {
        case .nowPlaying:
            if let media = data.nowPlaying {
                let progress: Double?
                if let position = media.position, let duration = media.duration, duration > 0 {
                    progress = min(max(position / duration, 0), 1)
                } else {
                    progress = nil
                }
                let itemActions: [PersonalHubAction] = media.lyrics == nil ? [] : [
                    .init(id: "copyToDevice", label: "Copy lyrics", symbol: "text.quote")
                ]
                return .init(
                    id: id,
                    availability: .ready,
                    summary: media.title,
                    detail: [media.artist, media.album, media.appName].filter { !$0.isEmpty }.joined(separator: " · "),
                    items: [
                        .init(
                            id: "current",
                            title: media.title,
                            subtitle: media.artist,
                            detail: media.lyrics ?? media.album,
                            symbol: media.isPlaying ? "speaker.wave.2.fill" : "pause.fill",
                            progress: progress,
                            actions: itemActions
                        )
                    ],
                    actions: [
                        .init(id: "previous", label: "Previous", symbol: "backward.fill"),
                        .init(
                            id: "playPause",
                            label: media.isPlaying ? "Pause" : "Play",
                            symbol: media.isPlaying ? "pause.fill" : "play.fill",
                            role: .primary
                        ),
                        .init(id: "next", label: "Next", symbol: "forward.fill")
                    ]
                )
            }
            return .init(
                id: id,
                availability: data.mediaPermissionError == nil ? .partial : .permissionRequired,
                summary: data.mediaPermissionError ?? "Play something in Music or Spotify"
            )

        case .shelf:
            return .init(
                id: id,
                availability: .ready,
                summary: data.shelf.isEmpty ? "Clipboard history is empty" : "\(data.shelf.count) recent clips",
                detail: "Stored locally on this Mac",
                items: data.shelf.prefix(12).map { entry in
                    .init(
                        id: entry.id,
                        title: entry.title,
                        subtitle: Self.relativeDate(entry.capturedAt),
                        detail: entry.value,
                        symbol: "doc.on.clipboard",
                        actions: [
                            .init(id: "copyToDevice", label: "Copy here", symbol: "doc.on.doc", role: .primary),
                            .init(id: "remove", label: "Remove", symbol: "trash", role: .destructive, targetID: entry.id)
                        ]
                    )
                }
            )

        case .notes:
            return .init(
                id: id,
                availability: .ready,
                summary: data.notes.isEmpty ? "No notes yet" : "\(data.notes.count) notes",
                items: data.notes.prefix(20).map { note in
                    .init(
                        id: note.id,
                        title: note.title,
                        subtitle: Self.relativeDate(note.updatedAt),
                        detail: note.text,
                        symbol: "note.text",
                        actions: [
                            .init(id: "copyToDevice", label: "Copy here", symbol: "doc.on.doc"),
                            .init(id: "append", label: "Append", symbol: "text.append", targetID: note.id),
                            .init(id: "replace", label: "Edit", symbol: "square.and.pencil", targetID: note.id),
                            .init(id: "delete", label: "Delete", symbol: "trash", role: .destructive, targetID: note.id)
                        ]
                    )
                },
                actions: [.init(id: "add", label: "Add note", symbol: "plus", role: .primary)]
            )

        case .system:
            guard let system = data.system else {
                return .init(id: id, availability: .loading, summary: "Reading this Mac")
            }
            let load = String(format: "%.2f", system.load1)
            let memory = system.memoryPercent.map { " · memory \($0)%" } ?? ""
            return .init(
                id: id,
                availability: .ready,
                summary: "Load \(load)\(memory)",
                detail: "\(system.processorCount) cores · thermal \(system.thermalState) · up \(Self.duration(system.uptime))",
                actions: [.init(id: "refresh", label: "Refresh", symbol: "arrow.clockwise")]
            )

        case .calendar:
            guard glances.calendarAuthorized else {
                return .init(
                    id: id,
                    availability: .permissionRequired,
                    summary: "Calendar access is required on the Mac"
                )
            }
            let events = glances.upcomingEvents
            return .init(
                id: id,
                availability: .ready,
                summary: events.isEmpty ? "No events in the next two weeks" : "\(events.count) upcoming",
                detail: "Two-week agenda from the Mac's calendars",
                items: events.map { event in
                    var actions: [PersonalHubAction] = []
                    if let joinURL = event.joinURL {
                        actions.append(.init(
                            id: "join",
                            label: "Join here",
                            symbol: "video.fill",
                            role: .primary,
                            targetID: event.id,
                            deepLink: joinURL
                        ))
                        actions.append(.init(
                            id: "openOnMac",
                            label: "Open on Mac",
                            symbol: "macbook",
                            targetID: event.id
                        ))
                    }
                    actions.append(.init(
                        id: "delete",
                        label: "Delete",
                        symbol: "trash",
                        role: .destructive,
                        targetID: event.id
                    ))
                    return .init(
                        id: event.id,
                        title: event.title,
                        subtitle: "\(Self.eventTime(event)) · \(event.calendarTitle)",
                        symbol: "calendar",
                        actions: actions
                    )
                },
                actions: [.init(id: "add", label: "Add event", symbol: "plus", role: .primary)]
            )

        case .reminders:
            guard glances.remindersAuthorized else {
                return .init(
                    id: id,
                    availability: .permissionRequired,
                    summary: "Reminders access is required on the Mac"
                )
            }
            return .init(
                id: id,
                availability: .ready,
                summary: glances.reminders.isEmpty
                    ? "No open tasks in the selected lists"
                    : "\(glances.reminders.count) open",
                items: glances.reminders.map { reminder in
                    .init(
                        id: reminder.id,
                        title: reminder.title,
                        subtitle: [reminder.due.map(Self.taskDue), reminder.calendarTitle]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        symbol: "circle",
                        actions: [
                            .init(
                                id: "complete",
                                label: "Complete",
                                symbol: "checkmark.circle.fill",
                                role: .primary,
                                targetID: reminder.id
                            ),
                            .init(
                                id: "delete",
                                label: "Delete",
                                symbol: "trash",
                                role: .destructive,
                                targetID: reminder.id
                            )
                        ]
                    )
                },
                actions: [
                    .init(id: "add", label: "Add task", symbol: "plus", role: .primary)
                ]
            )

        case .weather:
            if let weather = glances.weather {
                let location = glances.weatherLocationLabel.map { " · \($0)" } ?? ""
                return .init(
                    id: id,
                    availability: .ready,
                    summary: "\(weather.temperatureF)° · \(weather.summary)\(location)",
                    actions: [.init(id: "refresh", label: "Refresh", symbol: "arrow.clockwise")]
                )
            }
            return .init(
                id: id,
                availability: .loading,
                summary: glances.statusLine ?? "Finding weather"
            )

        case .agents:
            let sessions = appState.sessions.sorted { $0.value.lastActivity > $1.value.lastActivity }
            let waiting = appState.permissionQueue.count + appState.questionQueue.count
            return .init(
                id: id,
                availability: .ready,
                summary: waiting > 0 ? "\(waiting) waiting · \(sessions.count) sessions" : "\(sessions.count) sessions",
                items: sessions.prefix(12).map { sessionID, session in
                    .init(
                        id: sessionID,
                        title: session.displayName,
                        subtitle: session.sourceLabel,
                        detail: String(describing: session.status),
                        symbol: "terminal"
                    )
                }
            )

        case .downloads:
            let summary: String
            if let download = utilities.primaryDownload {
                summary = download.percent.map { "\(download.name) · \($0)%" } ?? download.name
            } else if let completed = utilities.recentDownloadCompleted {
                summary = "Finished \(completed)"
            } else {
                summary = "No active downloads"
            }
            return .init(
                id: id,
                availability: .partial,
                summary: summary,
                items: utilities.downloads.map { download in
                    .init(
                        id: download.id,
                        title: download.name,
                        subtitle: download.percent.map { "\($0)%" },
                        symbol: "arrow.down.circle",
                        progress: download.progress,
                        actions: [
                            .init(id: "reveal", label: "Reveal on Mac", symbol: "folder", targetID: download.id)
                        ]
                    )
                }
            )

        case .bluetooth:
            return .init(
                id: id,
                availability: utilities.bluetoothDevices.isEmpty ? .loading : .ready,
                summary: utilities.bluetoothDevices.isEmpty
                    ? (utilities.bluetoothError ?? "Reading paired devices")
                    : "\(utilities.bluetoothDevices.filter(\.isConnected).count) connected · \(utilities.bluetoothDevices.count) paired",
                items: utilities.bluetoothDevices.map { device in
                    let battery = utilities.deviceBatteries.first {
                        $0.name.localizedCaseInsensitiveCompare(device.name) == .orderedSame
                    }
                    return .init(
                        id: device.id,
                        title: device.name,
                        subtitle: [device.isConnected ? "Connected" : "Not connected", device.kind, battery?.summary]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        symbol: device.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                        actions: [
                            .init(
                                id: device.isConnected ? "disconnect" : "connect",
                                label: device.isConnected ? "Disconnect" : "Connect",
                                symbol: device.isConnected ? "xmark.circle" : "link",
                                role: device.isConnected ? .destructive : .primary,
                                targetID: device.id
                            )
                        ]
                    )
                },
                actions: [.init(id: "refresh", label: "Refresh", symbol: "arrow.clockwise")]
            )

        case .battery:
            var batteryItems: [PersonalHubItem] = []
            if let mac = data.macBattery {
                batteryItems.append(.init(
                    id: "mac",
                    title: "MacBook",
                    subtitle: [
                        "\(mac.percent)%",
                        mac.status,
                        mac.powerSource,
                        mac.healthPercent.map { "health \($0)%" },
                        mac.cycleCount.map { "\($0) cycles" },
                        mac.condition
                    ].compactMap { $0 }.joined(separator: " · "),
                    symbol: "laptopcomputer"
                ))
            }
            batteryItems.append(contentsOf: utilities.deviceBatteries.map { device in
                .init(id: device.id, title: device.name, subtitle: device.summary, symbol: "battery.75percent")
            })
            return .init(
                id: id,
                availability: data.macBattery == nil ? .partial : .ready,
                summary: data.macBattery.map { "Mac \($0.percent)% · \($0.status)" }
                    ?? utilities.lowBattery.map { "\($0.name) · \($0.summary)" }
                    ?? "Battery readings unavailable",
                items: batteryItems
            )

        case .audio:
            let devices = data.audioDevices.filter { $0.isInput || $0.isOutput }
            let active = devices.filter { $0.isDefaultInput || $0.isDefaultOutput }
            return .init(
                id: id,
                availability: devices.isEmpty ? .loading : .ready,
                summary: active.isEmpty
                    ? "\(devices.count) audio devices"
                    : active.map(\.name).joined(separator: " · "),
                items: devices.prefix(12).map { device in
                    let roles = [
                        device.isDefaultInput ? "Default input" : nil,
                        device.isDefaultOutput ? "Default output" : nil,
                        device.isInput && !device.isDefaultInput ? "Input" : nil,
                        device.isOutput && !device.isDefaultOutput ? "Output" : nil,
                    ].compactMap { $0 }.joined(separator: " · ")
                    var actions: [PersonalHubAction] = []
                    if device.isInput, !device.isDefaultInput {
                        actions.append(.init(
                            id: "setInput",
                            label: "Use input",
                            symbol: "mic.fill",
                            targetID: device.id
                        ))
                    }
                    if device.isOutput, !device.isDefaultOutput {
                        actions.append(.init(
                            id: "setOutput",
                            label: "Use output",
                            symbol: "speaker.wave.2.fill",
                            role: .primary,
                            targetID: device.id
                        ))
                    }
                    return .init(
                        id: device.id,
                        title: device.name,
                        subtitle: roles,
                        symbol: "speaker.wave.2",
                        actions: actions
                    )
                },
                actions: [.init(id: "openSettings", label: "Open Sound Settings", symbol: "slider.horizontal.3")]
            )

        case .quickToggles:
            let settings = data.quickSettings
            return .init(
                id: id,
                availability: .ready,
                summary: [
                    settings?.darkMode == true ? "Dark" : "Light",
                    settings?.outputMuted == true ? "Muted" : "Sound on"
                ].joined(separator: " · "),
                actions: [
                    .init(id: "darkMode", label: settings?.darkMode == true ? "Light" : "Dark", symbol: "circle.lefthalf.filled"),
                    .init(id: "mute", label: settings?.outputMuted == true ? "Unmute" : "Mute", symbol: "speaker.slash.fill"),
                    .init(id: "displaySleep", label: "Display off", symbol: "display", role: .destructive),
                    .init(id: "lockMac", label: "Lock Mac", symbol: "lock.fill", role: .destructive)
                ]
            )

        case .notifications:
            let count = appState.permissionQueue.count + appState.questionQueue.count
            return .init(
                id: id,
                availability: .partial,
                summary: count == 0 ? "No CodeIsland alerts" : "\(count) CodeIsland alerts"
            )

        case .github:
            guard let pullRequests = data.githubPullRequests else {
                return .init(
                    id: id,
                    availability: .permissionRequired,
                    summary: "Install and authenticate GitHub CLI on the Mac"
                )
            }
            return .init(
                id: id,
                availability: .ready,
                summary: pullRequests.isEmpty ? "No open pull requests" : "\(pullRequests.count) open pull requests",
                detail: "Authored by your current GitHub account",
                items: pullRequests.map { pullRequest in
                    .init(
                        id: pullRequest.id,
                        title: pullRequest.title,
                        subtitle: "\(pullRequest.repository)#\(pullRequest.number)\(pullRequest.isDraft ? " · Draft" : "")",
                        symbol: "arrow.triangle.pull",
                        actions: [
                            .init(
                                id: "open",
                                label: "Open",
                                symbol: "safari",
                                role: .primary,
                                targetID: pullRequest.id,
                                deepLink: pullRequest.url
                            )
                        ]
                    )
                }
            )

        case .windowManager:
            guard WindowManagerController.isAuthorized else {
                return .init(
                    id: id,
                    availability: .permissionRequired,
                    summary: "Accessibility access is required",
                    actions: [
                        .init(id: "openAccessibility", label: "Open Settings", symbol: "gearshape")
                    ]
                )
            }
            return .init(
                id: id,
                availability: .ready,
                summary: "Place the front Mac window",
                actions: [
                    .init(id: "left", label: "Left", symbol: "rectangle.lefthalf.inset.filled"),
                    .init(id: "maximize", label: "Maximize", symbol: "arrow.up.left.and.arrow.down.right", role: .primary),
                    .init(id: "right", label: "Right", symbol: "rectangle.righthalf.inset.filled")
                ]
            )

        case .teleprompter:
            let text = data.teleprompterText
            return .init(
                id: id,
                availability: .ready,
                summary: text.isEmpty ? "No script loaded" : "\(text.split(whereSeparator: \.isWhitespace).count) words ready",
                detail: "Saved locally on the Mac and mirrored only through the private hub",
                items: text.isEmpty ? [] : [
                    .init(
                        id: "current",
                        title: text.split(whereSeparator: \Character.isNewline).first.map(String.init) ?? "Current script",
                        detail: text,
                        symbol: "text.alignleft",
                        actions: [
                            .init(id: "presentOnDevice", label: "Present", symbol: "play.rectangle.fill", role: .primary),
                            .init(id: "copyToDevice", label: "Copy", symbol: "doc.on.doc")
                        ]
                    )
                ],
                actions: [.init(id: "set", label: text.isEmpty ? "Add script" : "Replace script", symbol: "square.and.pencil")]
            )

        case .camera:
            return .init(
                id: id,
                availability: .ready,
                summary: "Private camera pre-check",
                detail: "Preview stays on the device and is never sent to the Mac",
                actions: [
                    .init(id: "previewOnDevice", label: "Open preview", symbol: "camera.fill", role: .primary)
                ]
            )

        case .claude:
            var items: [PersonalHubItem] = []
            if let response = data.claudeLastResponse {
                items.append(.init(
                    id: "latest",
                    title: data.claudeLastPrompt ?? "Latest answer",
                    subtitle: "Claude Code · read-only",
                    detail: response,
                    symbol: "sparkles",
                    actions: [.init(id: "copyToDevice", label: "Copy", symbol: "doc.on.doc")]
                ))
            }
            return .init(
                id: id,
                availability: data.claudeBusy ? .loading : .ready,
                summary: data.claudeBusy ? "Claude is answering" : (data.claudeError ?? "Ask your authenticated Claude Code"),
                detail: "Read-only: tools are disabled; actions stay in CodeIsland's reviewed controls",
                items: items,
                actions: [.init(id: "ask", label: "Ask Claude", symbol: "sparkles", role: .primary)]
            )

        default:
            let definition = PersonalHubCatalog.definition(for: id)
            return .init(
                id: id,
                availability: .unavailable,
                summary: "\(definition.title) is not implemented yet"
            )
        }
    }

    private static func eventTime(_ event: GlancesModel.EventInfo) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }

    private static func taskDue(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Due \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private static func actionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}
