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
    private let glances: GlancesModel
    private let utilities: PersonalUtilitiesModel
    private let data: PersonalHubDataModel
    private let configurationStore: PersonalHubConfigurationStore

    init(
        glances: GlancesModel? = nil,
        utilities: PersonalUtilitiesModel? = nil,
        data: PersonalHubDataModel? = nil,
        configurationStore: PersonalHubConfigurationStore? = nil
    ) {
        self.glances = glances ?? .shared
        self.utilities = utilities ?? .shared
        self.data = data ?? .shared
        self.configurationStore = configurationStore ?? .shared
    }

    func shelfFileURL(id: String) -> URL? {
        data.shelfFileURL(id: id)
    }

    func recentDownloadFileURL(id: String) -> URL? {
        utilities.recentDownloadFileURL(id: id)
    }

    func snapshot(
        appState: AppState,
        requestedMode: PersonalHubMode,
        calendarReferenceDate: Date? = nil,
        calendarSelectedDate: Date? = nil,
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
        let configuration = configurationStore.configuration
        let moduleIDs = configuration.rack(for: resolvedMode)

        return PersonalHubSnapshot(
            serverName: serverName,
            requestedMode: requestedMode,
            resolvedMode: resolvedMode,
            modules: moduleIDs.map {
                moduleSnapshot(
                    id: $0,
                    appState: appState,
                    calendarReferenceDate: calendarReferenceDate,
                    calendarSelectedDate: calendarSelectedDate
                )
            },
            configuration: configuration,
            dayProgress: PersonalHubConfiguration.dayProgress()
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
        case (.quickToggles, "setModeRack"):
            guard let mutation = PersonalHubConfigurationMutation.decodeActionValue(intent.value),
                  let mode = mutation.mode,
                  let modules = mutation.modules else {
                return .failure(.invalid("Mode rack settings are incomplete"))
            }
            do {
                try configurationStore.updateRack(mode: mode, modules: modules)
                return .success(.init(executed: true, message: "\(mode.rawValue.capitalized) rack updated"))
            } catch {
                return .failure(.failed(error.localizedDescription))
            }

        case (.quickToggles, "setDashboard"):
            guard let mutation = PersonalHubConfigurationMutation.decodeActionValue(intent.value),
                  let enabled = mutation.dashboardEnabled else {
                return .failure(.invalid("Dashboard setting is incomplete"))
            }
            do {
                try configurationStore.setDashboardEnabled(enabled)
                return .success(.init(
                    executed: true,
                    message: enabled ? "Dashboard enabled" : "Dashboard hidden"
                ))
            } catch {
                return .failure(.failed(error.localizedDescription))
            }

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
                  let draft = PersonalHubNoteDraft.decodeActionValue(intent.value),
                  data.replaceNote(
                    id: targetID,
                    rawText: draft.text,
                    expectedRevision: draft.baseRevision,
                    category: draft.category
                  ) else {
                return .failure(.invalid("The note changed before this edit could be applied. Refresh and review it again."))
            }
            return .success(.init(executed: true, message: "Note updated"))

        case (.notes, "append"):
            guard let targetID = intent.targetID,
                  let value = intent.value,
                  data.appendToNote(id: targetID, rawText: value) else {
                return .failure(.invalid("Note is no longer available"))
            }
            return .success(.init(executed: true, message: "Text appended to note"))

        case (.notes, "setCategory"):
            guard let targetID = intent.targetID,
                  let draft = PersonalHubNoteDraft.decodeActionValue(intent.value),
                  let revision = draft.baseRevision,
                  data.setNoteCategory(id: targetID, rawCategory: draft.category, expectedRevision: revision) else {
                return .failure(.invalid("The note changed before its category could be updated. Refresh and try again."))
            }
            return .success(.init(executed: true, message: "Note category updated"))

        case (.notes, "undo"):
            guard let targetID = intent.targetID, data.undoNote(id: targetID) else {
                return .failure(.invalid("No note change is available to undo"))
            }
            return .success(.init(executed: true, message: "Last note change undone"))

        case (.notes, "toggleChecklist"):
            guard let targetID = intent.targetID,
                  let mutation = PersonalHubChecklistMutation.decodeActionValue(intent.value),
                  data.toggleChecklistLine(
                    id: targetID,
                    lineIndex: mutation.lineIndex,
                    expectedRevision: mutation.baseRevision
                  ) else {
                return .failure(.invalid("The checklist changed. Refresh and review it again."))
            }
            return .success(.init(executed: true, message: "Checklist updated"))

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

        case (.claude, "plan"):
            guard let value = intent.value, data.planClaudeActions(value) else {
                return .failure(.failed(data.claudeError ?? "Claude is already working"))
            }
            return .success(.init(executed: true, message: "Claude is preparing reviewable actions"))

        case (.claude, "applyProposal"):
            guard let targetID = intent.targetID,
                  let proposal = data.claudeProposals.first(where: { $0.id == targetID }) else {
                return .failure(.invalid("This Claude proposal is no longer available"))
            }
            let applied: Bool
            switch proposal.kind {
            case .reminder:
                applied = glances.addReminder(title: proposal.title, due: proposal.due)
            case .note:
                applied = data.addNote(proposal.text ?? proposal.title)
            case .calendar:
                guard let start = proposal.start, let end = proposal.end else {
                    return .failure(.invalid("This calendar proposal is incomplete"))
                }
                applied = glances.addEvent(.init(
                    title: proposal.title,
                    start: start,
                    end: end,
                    joinURL: proposal.joinURL,
                    notes: proposal.notes
                ))
            }
            guard applied else {
                return .failure(.failed("The proposed \(proposal.summary.lowercased()) could not be created"))
            }
            data.removeClaudeProposal(id: targetID)
            return .success(.init(executed: true, message: "\(proposal.summary) created"))

        case (.shelf, "remove"):
            guard let targetID = intent.targetID, data.removeShelfEntry(id: targetID) else {
                return .failure(.invalid("Shelf item is no longer available"))
            }
            return .success(.init(executed: true, message: "Shelf item removed"))

        case (.shelf, "revealOnMac"):
            guard let targetID = intent.targetID, let url = data.shelfFileURL(id: targetID) else {
                return .failure(.invalid("Shelf file is no longer available"))
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return .success(.init(executed: true, message: "Shelf file revealed on the Mac"))

        case (.nowPlaying, "playPause"), (.nowPlaying, "next"), (.nowPlaying, "previous"),
             (.nowPlaying, "seekBack"), (.nowPlaying, "seekForward"), (.nowPlaying, "seek"),
             (.nowPlaying, "playQueueItem"):
            guard data.runMediaCommand(
                intent.actionID,
                targetID: intent.targetID,
                value: intent.value
            ) else {
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

        case (.audio, "volumeDown"), (.audio, "volumeUp"):
            guard data.changeOutputVolume(by: intent.actionID == "volumeDown" ? -10 : 10) else {
                return .failure(.failed("Could not change Mac output volume"))
            }
            return .success(.init(executed: true, message: "Mac output volume changed"))

        case (.audio, "setVolume"):
            guard let value = intent.value,
                  let volume = Int(value),
                  (0...100).contains(volume),
                  data.setOutputVolume(volume) else {
                return .failure(.failed("Could not set Mac output volume"))
            }
            return .success(.init(executed: true, message: "Mac output volume set to \(volume)%"))

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
                  glances.addReminder(title: draft.title, due: draft.due, calendarID: draft.calendarID) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not add the task"))
            }
            return .success(.init(executed: true, message: "Task added"))

        case (.reminders, "addList"):
            guard let value = intent.value, glances.createReminderList(title: value) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not create the list"))
            }
            return .success(.init(executed: true, message: "Reminders list created"))

        case (.reminders, "deleteList"):
            guard let targetID = intent.targetID, glances.deleteReminderList(id: targetID) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not delete the list"))
            }
            return .success(.init(executed: true, message: "Reminders list deleted"))

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            glances.complete(reminder)
            return .success(.init(executed: true, message: "Task completed"))

        case (.reminders, "delete"):
            guard let targetID = intent.targetID,
                  let reminder = (glances.reminders + glances.completedReminders)
                    .first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            guard glances.deleteReminder(reminder) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not delete the task"))
            }
            return .success(.init(executed: true, message: "Task deleted"))

        case (.reminders, "restore"):
            guard let targetID = intent.targetID,
                  let reminder = glances.completedReminders.first(where: { $0.id == targetID }),
                  glances.restoreReminder(reminder) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not restore the task"))
            }
            return .success(.init(executed: true, message: "Task restored"))

        case (.reminders, "moveTop"), (.reminders, "moveUp"), (.reminders, "moveDown"):
            guard let targetID = intent.targetID else {
                return .failure(.invalid("Task is no longer available"))
            }
            let direction: String
            switch intent.actionID {
            case "moveTop": direction = "top"
            case "moveUp": direction = "up"
            default: direction = "down"
            }
            guard glances.moveReminder(id: targetID, direction: direction) else {
                return .failure(.invalid("Task is no longer available"))
            }
            return .success(.init(executed: true, message: "Task order updated"))

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

        case (.calendar, "edit"):
            guard let targetID = intent.targetID,
                  let draft = PersonalHubCalendarDraft.decodeActionValue(intent.value),
                  glances.updateEvent(id: targetID, draft: draft) else {
                return .failure(.failed(glances.calendarMutationError ?? "Could not update the event"))
            }
            return .success(.init(executed: true, message: "Event updated"))

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID }),
                  let joinURL = event.joinURL
            else { return .failure(.invalid("Meeting link is no longer available")) }
            NSWorkspace.shared.open(joinURL)
            return .success(.init(executed: true, message: "Meeting opened on the Mac"))

        case (.downloads, "refresh"):
            utilities.refreshDownloads()
            return .success(.init(executed: true, message: "Downloads refreshed"))

        case (.downloads, "reveal"):
            guard let targetID = intent.targetID,
                  let downloadURL = utilities.downloadItemURL(id: targetID)
            else { return .failure(.invalid("Download is no longer available")) }
            NSWorkspace.shared.activateFileViewerSelecting([downloadURL])
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
        case (.quickToggles, "setModeRack"):
            guard let mutation = PersonalHubConfigurationMutation.decodeActionValue(intent.value),
                  let mode = mutation.mode,
                  mode != .auto,
                  let modules = mutation.modules else {
                return .failure(.invalid("Choose a Home, Work, or Code rack"))
            }
            var seen = Set<PersonalHubModuleID>()
            let unique = modules.filter { seen.insert($0).inserted }
            guard !unique.isEmpty else {
                return .failure(.invalid("Keep at least one module in this rack"))
            }
            guard unique == modules else {
                return .failure(.invalid("A module can appear only once in a rack"))
            }
            let names = unique.map { PersonalHubCatalog.definition(for: $0).title }.joined(separator: ", ")
            return .success("Set the \(mode.rawValue.capitalized) rack to: \(names)")

        case (.quickToggles, "setDashboard"):
            guard let mutation = PersonalHubConfigurationMutation.decodeActionValue(intent.value),
                  let enabled = mutation.dashboardEnabled else {
                return .failure(.invalid("Choose whether to show the dashboard"))
            }
            return .success(enabled ? "Show the dashboard and day progress" : "Hide the dashboard and day progress")

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
            let draft = intent.actionID == "replace"
                ? PersonalHubNoteDraft.decodeActionValue(intent.value)
                : intent.value.map { PersonalHubNoteDraft(text: $0) }
            let value = draft?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty else { return .failure(.invalid("Enter note text")) }
            let limit = intent.actionID == "append" ? max(20_000 - note.text.count - 1, 0) : 20_000
            guard value.count <= limit else { return .failure(.invalid("Note is too long")) }
            if let baseRevision = draft?.baseRevision, baseRevision != note.currentRevision {
                return .failure(.invalid("This note has a newer revision. Refresh before replacing it."))
            }
            return .success(intent.actionID == "append"
                ? "Append text to “\(note.title)”"
                : "Replace the contents of “\(note.title)”")

        case (.notes, "setCategory"):
            guard let targetID = intent.targetID,
                  let note = data.notes.first(where: { $0.id == targetID }),
                  let draft = PersonalHubNoteDraft.decodeActionValue(intent.value),
                  draft.baseRevision == note.currentRevision else {
                return .failure(.invalid("This note has a newer revision. Refresh before changing its category."))
            }
            let category = draft.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard category.count <= 40 else { return .failure(.invalid("Category is too long")) }
            return .success(category.isEmpty
                ? "Clear the category from “\(note.title)”"
                : "Set “\(note.title)” category to “\(category)”")

        case (.notes, "undo"):
            guard let targetID = intent.targetID,
                  let note = data.notes.first(where: { $0.id == targetID }),
                  note.canUndo else { return .failure(.invalid("No note change is available to undo")) }
            return .success("Undo the last change to “\(note.title)”")

        case (.notes, "toggleChecklist"):
            guard let targetID = intent.targetID,
                  let note = data.notes.first(where: { $0.id == targetID }),
                  let mutation = PersonalHubChecklistMutation.decodeActionValue(intent.value),
                  mutation.baseRevision == note.currentRevision,
                  let line = note.checklist.first(where: { $0.lineIndex == mutation.lineIndex }) else {
                return .failure(.invalid("This checklist changed. Refresh before updating it."))
            }
            return .success("Mark “\(line.title)” as \(line.isCompleted ? "not done" : "done")")

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

        case (.claude, "plan"):
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !data.claudeBusy else { return .failure(.invalid("Claude is already working")) }
            guard !value.isEmpty else { return .failure(.invalid("Describe what Claude should propose")) }
            guard value.count <= 20_000 else { return .failure(.invalid("Request is too long")) }
            return .success("Ask Claude to propose CodeIsland actions for: “\(value.prefix(160))\(value.count > 160 ? "…" : "")”")

        case (.claude, "applyProposal"):
            guard let targetID = intent.targetID,
                  let proposal = data.claudeProposals.first(where: { $0.id == targetID }) else {
                return .failure(.invalid("This Claude proposal is no longer available"))
            }
            switch proposal.kind {
            case .reminder:
                return .success("Create \(proposal.due == nil ? "task" : "reminder") “\(proposal.title)”")
            case .note:
                return .success("Create note “\(proposal.title)”")
            case .calendar:
                guard let start = proposal.start, let end = proposal.end else {
                    return .failure(.invalid("This calendar proposal is incomplete"))
                }
                return .success("Add “\(proposal.title)” from \(Self.eventDate(start)) to \(Self.eventDate(end))")
            }

        case (.shelf, "remove"):
            guard let targetID = intent.targetID,
                  let entry = data.shelf.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Shelf item is no longer available")) }
            return .success("Remove “\(entry.title)” from Shelf")

        case (.shelf, "revealOnMac"):
            guard let targetID = intent.targetID,
                  let entry = data.shelf.first(where: { $0.id == targetID }),
                  data.shelfFileURL(id: targetID) != nil
            else { return .failure(.invalid("Shelf file is no longer available")) }
            return .success("Reveal “\(entry.title)” on the Mac")

        case (.nowPlaying, "playPause"):
            guard let media = data.nowPlaying else { return .failure(.invalid("Nothing is playing")) }
            return .success("\(media.isPlaying ? "Pause" : "Play") “\(media.title)”")

        case (.nowPlaying, "next"):
            guard data.nowPlaying != nil else { return .failure(.invalid("Nothing is playing")) }
            return .success("Skip to the next track")

        case (.nowPlaying, "previous"):
            guard data.nowPlaying != nil else { return .failure(.invalid("Nothing is playing")) }
            return .success("Return to the previous track")

        case (.nowPlaying, "seekBack"):
            guard data.nowPlaying?.position != nil else { return .failure(.invalid("Playback position is unavailable")) }
            return .success("Rewind the current track 15 seconds")

        case (.nowPlaying, "seekForward"):
            guard data.nowPlaying?.position != nil else { return .failure(.invalid("Playback position is unavailable")) }
            return .success("Advance the current track 15 seconds")

        case (.nowPlaying, "seek"):
            guard let value = intent.value,
                  let requested = Double(value),
                  let duration = data.nowPlaying?.duration,
                  let destination = PersonalHubDataModel.clampedSeekPosition(requested, duration: duration) else {
                return .failure(.invalid("Choose a valid position in the current track"))
            }
            return .success("Seek the current track to \(Self.playbackTime(destination))")

        case (.nowPlaying, "playQueueItem"):
            guard let targetID = intent.targetID,
                  let item = data.nowPlaying?.queue.first(where: { $0.id == targetID }) else {
                return .failure(.invalid("That queued track is no longer available"))
            }
            return .success("Play “\(item.title)” next from the current Music queue")

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

        case (.audio, "volumeDown"), (.audio, "volumeUp"):
            let current = data.quickSettings?.outputVolume
            let target = current.map { min(max($0 + (intent.actionID == "volumeDown" ? -10 : 10), 0), 100) }
            return .success(target.map { "Set Mac output volume to \($0)%" } ?? "Change Mac output volume by 10%")

        case (.audio, "setVolume"):
            guard let value = intent.value, let volume = Int(value), (0...100).contains(volume) else {
                return .failure(.invalid("Choose an output volume from 0 to 100"))
            }
            return .success("Set Mac output volume to \(volume)%")

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
            if let calendarID = draft.calendarID,
               !glances.reminderCalendars.contains(where: { $0.id == calendarID && $0.isWritable }) {
                return .failure(.invalid("That Reminders list is no longer writable"))
            }
            let due = draft.due.map { " due \(Self.actionDate($0))" } ?? ""
            let list = draft.calendarID.flatMap { selected in
                glances.reminderCalendars.first(where: { $0.id == selected })?.title
            } ?? "the selected Reminders list"
            return .success("Add “\(value)” to \(list)\(due)")

        case (.reminders, "addList"):
            let value = intent.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard glances.remindersAuthorized else {
                return .failure(.invalid("Reminders access is required on the Mac"))
            }
            guard !value.isEmpty, value.count <= 100 else {
                return .failure(.invalid("Enter a list name"))
            }
            guard !glances.reminderCalendars.contains(where: {
                $0.title.localizedCaseInsensitiveCompare(value) == .orderedSame
            }) else { return .failure(.invalid("A list with that name already exists")) }
            return .success("Create Reminders list “\(value)”")

        case (.reminders, "deleteList"):
            guard let targetID = intent.targetID,
                  let calendar = glances.reminderCalendars.first(where: { $0.id == targetID })
            else { return .failure(.invalid("List is no longer available")) }
            guard !calendar.isDefault, calendar.isWritable else {
                return .failure(.invalid("The default or a read-only list cannot be deleted"))
            }
            return .success("Delete Reminders list “\(calendar.title)” and its tasks")

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            return .success("Mark “\(reminder.title)” complete")

        case (.reminders, "delete"):
            guard let targetID = intent.targetID,
                  let reminder = (glances.reminders + glances.completedReminders)
                    .first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            return .success("Delete task “\(reminder.title)”")

        case (.reminders, "restore"):
            guard let targetID = intent.targetID,
                  let reminder = glances.completedReminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Completed task is no longer available")) }
            return .success("Restore “\(reminder.title)” to open tasks")

        case (.reminders, "moveTop"), (.reminders, "moveUp"), (.reminders, "moveDown"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            let destination: String
            switch intent.actionID {
            case "moveTop": destination = "the top"
            case "moveUp": destination = "up"
            default: destination = "down"
            }
            return .success("Move “\(reminder.title)” \(destination)")

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
            guard event.isEditable else { return .failure(.invalid("This calendar is read-only")) }
            return .success("Delete event “\(event.title)”")

        case (.calendar, "edit"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID }),
                  event.isEditable else { return .failure(.invalid("Event is no longer editable")) }
            guard let draft = PersonalHubCalendarDraft.decodeActionValue(intent.value) else {
                return .failure(.invalid("Enter an event title and time"))
            }
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 500, draft.end > draft.start else {
                return .failure(.invalid("Enter a title and an end time after the start"))
            }
            if let url = draft.joinURL, !GlancesModel.isTrustedJoinURL(url) {
                return .failure(.invalid("Use a supported HTTPS meeting link"))
            }
            return .success("Update “\(event.title)” to “\(title)” on \(Self.actionDate(draft.start))")

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.upcomingEvents.first(where: { $0.id == targetID }),
                  event.joinURL != nil
            else { return .failure(.invalid("Meeting link is no longer available")) }
            return .success("Open “\(event.title)” on the Mac")

        case (.downloads, "refresh"):
            return .success("Refresh Downloads")

        case (.downloads, "reveal"):
            guard let targetID = intent.targetID,
                  let downloadURL = utilities.downloadItemURL(id: targetID)
            else { return .failure(.invalid("Download is no longer available")) }
            return .success("Reveal “\(downloadURL.lastPathComponent)” on the Mac")

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
        appState: AppState,
        calendarReferenceDate: Date?,
        calendarSelectedDate: Date?
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
                let currentItem = PersonalHubItem(
                    id: "current",
                    title: media.title,
                    subtitle: media.artist,
                    detail: media.lyrics ?? media.album,
                    symbol: media.isPlaying ? "speaker.wave.2.fill" : "pause.fill",
                    progress: progress,
                    artworkDataURL: media.artworkJPEG.map {
                        "data:image/jpeg;base64,\($0.base64EncodedString())"
                    },
                    mediaPosition: media.position,
                    mediaDuration: media.duration,
                    actions: itemActions
                )
                let queueItems = media.queue.map { queued in
                    PersonalHubItem(
                        id: "queue:\(queued.id)",
                        title: queued.title,
                        subtitle: [queued.artist, queued.album].filter { !$0.isEmpty }.joined(separator: " · "),
                        symbol: "text.line.first.and.arrowtriangle.forward",
                        actions: [
                            .init(
                                id: "playQueueItem",
                                label: "Play",
                                symbol: "play.fill",
                                targetID: queued.id
                            )
                        ]
                    )
                }
                var mediaActions: [PersonalHubAction] = [
                    .init(id: "previous", label: "Previous", symbol: "backward.fill")
                ]
                if media.position != nil {
                    mediaActions.append(.init(id: "seekBack", label: "−15s", symbol: "gobackward.15"))
                }
                mediaActions.append(.init(
                    id: "playPause",
                    label: media.isPlaying ? "Pause" : "Play",
                    symbol: media.isPlaying ? "pause.fill" : "play.fill",
                    role: .primary
                ))
                if media.position != nil {
                    mediaActions.append(.init(id: "seekForward", label: "+15s", symbol: "goforward.15"))
                }
                mediaActions.append(.init(id: "next", label: "Next", symbol: "forward.fill"))
                return .init(
                    id: id,
                    availability: .ready,
                    summary: media.title,
                    detail: [
                        media.artist,
                        media.album,
                        media.appName,
                        media.appName == "Spotify" ? "Spotify does not expose its queue to macOS automation" : nil
                    ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                    items: [currentItem] + queueItems,
                    actions: mediaActions
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
                summary: data.shelf.isEmpty ? "Shelf is empty" : "\(data.shelf.count) recent items",
                detail: "Private Mac storage · files up to 100 MB transfer to paired devices",
                items: data.shelf.prefix(12).map { entry in
                    var actions: [PersonalHubAction]
                    if entry.filePath != nil {
                        actions = [
                            .init(id: "remove", label: "Remove", symbol: "trash", role: .destructive, targetID: entry.id),
                        ]
                        if data.shelfFileURL(id: entry.id) != nil {
                            actions.insert(
                                .init(id: "revealOnMac", label: "Reveal on Mac", symbol: "folder", targetID: entry.id),
                                at: 0
                            )
                        }
                        if data.shelfFileIsTransferable(id: entry.id) {
                            actions.insert(
                                .init(id: "downloadToDevice", label: "Download", symbol: "square.and.arrow.down", role: .primary, targetID: entry.id),
                                at: 0
                            )
                        }
                    } else {
                        actions = [
                            .init(id: "copyToDevice", label: "Copy here", symbol: "doc.on.doc", role: .primary),
                            .init(id: "remove", label: "Remove", symbol: "trash", role: .destructive, targetID: entry.id)
                        ]
                    }
                    return .init(
                        id: entry.id,
                        title: entry.title,
                        subtitle: [
                            entry.source.flatMap(Self.shelfSourceLabel),
                            entry.byteCount.map(Self.fileSize),
                            Self.relativeDate(entry.capturedAt),
                            entry.filePath != nil && !data.shelfFileIsTransferable(id: entry.id)
                                ? "Mac only"
                                : nil,
                        ].compactMap { $0 }.joined(separator: " · "),
                        detail: entry.filePath == nil ? entry.value : nil,
                        symbol: entry.filePath == nil ? "doc.on.clipboard" : "doc.fill",
                        actions: actions
                    )
                }
            )

        case .notes:
            let noteItems = data.notes.prefix(20).flatMap { note -> [PersonalHubItem] in
                let editorSeed = PersonalHubNoteDraft(
                    text: note.text,
                    category: note.category,
                    baseRevision: note.currentRevision
                ).encodedActionValue()
                var actions: [PersonalHubAction] = [
                    .init(id: "copyToDevice", label: "Copy here", symbol: "doc.on.doc"),
                    .init(id: "append", label: "Append", symbol: "text.append", targetID: note.id),
                    .init(
                        id: "replace",
                        label: "Edit",
                        symbol: "square.and.pencil",
                        targetID: note.id,
                        value: editorSeed
                    ),
                    .init(
                        id: "setCategory",
                        label: "Category",
                        symbol: "tag",
                        targetID: note.id,
                        value: editorSeed
                    )
                ]
                if note.canUndo {
                    actions.append(.init(
                        id: "undo",
                        label: "Undo",
                        symbol: "arrow.uturn.backward",
                        targetID: note.id
                    ))
                }
                actions.append(.init(
                    id: "delete",
                    label: "Delete",
                    symbol: "trash",
                    role: .destructive,
                    targetID: note.id
                ))
                let noteItem = PersonalHubItem(
                    id: note.id,
                    title: note.title,
                    subtitle: [note.category, Self.relativeDate(note.updatedAt), "rev \(note.currentRevision)"]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    detail: note.text,
                    symbol: "note.text",
                    actions: actions
                )
                let checklistItems = note.checklist.map { line in
                    PersonalHubItem(
                        id: "check:\(note.id):\(line.lineIndex)",
                        title: line.title,
                        subtitle: "Checklist · \(note.title)",
                        symbol: line.isCompleted ? "checkmark.square.fill" : "square",
                        actions: [
                            .init(
                                id: "toggleChecklist",
                                label: line.isCompleted ? "Reopen" : "Complete",
                                symbol: line.isCompleted ? "square" : "checkmark.square.fill",
                                role: line.isCompleted ? .normal : .primary,
                                targetID: note.id,
                                value: PersonalHubChecklistMutation(
                                    lineIndex: line.lineIndex,
                                    baseRevision: note.currentRevision
                                ).encodedActionValue()
                            )
                        ]
                    )
                }
                return [noteItem] + checklistItems
            }
            return .init(
                id: id,
                availability: .ready,
                summary: data.notes.isEmpty ? "No notes yet" : "\(data.notes.count) notes",
                detail: "Categories · checklists · 20-step undo · revision-safe edits",
                items: noteItems,
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
            let referenceDate = calendarReferenceDate ?? Date()
            let selectedDate = calendarSelectedDate ?? referenceDate
            let monthInfo = glances.calendarMonth(
                referenceDate: referenceDate,
                selectedDate: selectedDate
            )
            let selectedItems = monthInfo.selectedEvents.map(calendarItem)
            let calendarMonth = PersonalHubCalendarMonth(
                displayedMonth: monthInfo.month.displayedMonth,
                selectedDate: monthInfo.month.selectedDate,
                days: monthInfo.month.days,
                selectedEvents: selectedItems
            )
            return .init(
                id: id,
                availability: .ready,
                summary: events.isEmpty ? "No events in the next two weeks" : "\(events.count) upcoming",
                detail: "Month and two-week agenda from the Mac's calendars",
                items: events.map(calendarItem),
                actions: [.init(id: "add", label: "Add event", symbol: "plus", role: .primary)],
                calendarMonth: calendarMonth
            )

        case .reminders:
            guard glances.remindersAuthorized else {
                return .init(
                    id: id,
                    availability: .permissionRequired,
                    summary: "Reminders access is required on the Mac"
                )
            }
            let listItems: [PersonalHubItem] = glances.reminderCalendars.map { calendar in
                var actions: [PersonalHubAction] = []
                if calendar.isWritable, !calendar.isDefault {
                    actions.append(.init(
                        id: "deleteList",
                        label: "Delete list",
                        symbol: "trash",
                        role: .destructive,
                        targetID: calendar.id
                    ))
                }
                return .init(
                    id: "list:\(calendar.id)",
                    title: calendar.title,
                    subtitle: [calendar.sourceTitle, glances.selectedReminderCalendarIDs.contains(calendar.id) ? "Shown" : nil]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    detail: calendar.id,
                    symbol: "list.bullet",
                    actions: actions
                )
            }
            let openItems: [PersonalHubItem] = glances.reminders.enumerated().map { index, reminder in
                var actions: [PersonalHubAction] = [
                    .init(id: "complete", label: "Complete", symbol: "checkmark.circle.fill", role: .primary, targetID: reminder.id),
                    .init(id: "copyToDevice", label: "Copy", symbol: "doc.on.doc", targetID: reminder.id),
                ]
                if index > 0 {
                    actions.append(.init(id: "moveUp", label: "Up", symbol: "arrow.up", targetID: reminder.id))
                    actions.append(.init(id: "moveTop", label: "Top", symbol: "arrow.up.to.line", targetID: reminder.id))
                }
                if index + 1 < glances.reminders.count {
                    actions.append(.init(id: "moveDown", label: "Down", symbol: "arrow.down", targetID: reminder.id))
                }
                actions.append(.init(id: "delete", label: "Delete", symbol: "trash", role: .destructive, targetID: reminder.id))
                return .init(
                    id: reminder.id,
                    title: reminder.title,
                    subtitle: [reminder.due.map(Self.taskDue), reminder.calendarTitle]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    detail: reminder.title,
                    symbol: "circle",
                    actions: actions
                )
            }
            let completedItems: [PersonalHubItem] = glances.completedReminders.prefix(8).map { reminder in
                .init(
                    id: reminder.id,
                    title: reminder.title,
                    subtitle: ["Completed", reminder.completionDate.map(Self.taskCompleted), reminder.calendarTitle]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    detail: reminder.title,
                    symbol: "checkmark.circle.fill",
                    actions: [
                        .init(id: "restore", label: "Restore", symbol: "arrow.uturn.backward", role: .primary, targetID: reminder.id),
                        .init(id: "copyToDevice", label: "Copy", symbol: "doc.on.doc", targetID: reminder.id),
                        .init(id: "delete", label: "Delete", symbol: "trash", role: .destructive, targetID: reminder.id),
                    ]
                )
            }
            return .init(
                id: id,
                availability: .ready,
                summary: glances.reminders.isEmpty
                    ? "No open tasks in the selected lists"
                    : "\(glances.reminders.count) open",
                detail: "\(glances.reminderCalendars.count) lists · \(glances.completedReminders.count) recently completed",
                items: listItems + openItems + completedItems,
                actions: [
                    .init(id: "add", label: "Add task", symbol: "plus", role: .primary),
                    .init(id: "addList", label: "New list", symbol: "list.bullet.badge.plus")
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
            let attentionIDs = SessionAttentionRouter.orderedSessionIDs(
                appState.sessions.map { sessionID, session in
                    SessionAttentionCandidate(
                        id: sessionID,
                        status: session.status,
                        lastActivity: session.lastActivity
                    )
                }
            )
            let recentIDs = appState.sessions
                .sorted { $0.value.lastActivity > $1.value.lastActivity }
                .map(\.key)
            let visibleIDs = attentionIDs.isEmpty ? Array(recentIDs.prefix(1)) : attentionIDs
            let waiting = appState.permissionQueue.count + appState.questionQueue.count
            let running = appState.sessions.values.filter {
                $0.status == .running || $0.status == .processing
            }.count
            return .init(
                id: id,
                availability: .ready,
                summary: waiting > 0
                    ? "\(waiting) needs you · \(running) running"
                    : (running > 0 ? "\(running) running · no decisions waiting" : "No decisions waiting"),
                detail: "\(appState.sessions.count) total sessions",
                items: visibleIDs.prefix(6).compactMap { sessionID in
                    guard let session = appState.sessions[sessionID] else { return nil }
                    return .init(
                        id: sessionID,
                        title: session.displayName,
                        subtitle: "\(Self.agentAttentionLabel(session.status)) · \(session.sourceLabel)",
                        detail: String(describing: session.status),
                        symbol: Self.agentAttentionSymbol(session.status)
                    )
                }
            )

        case .downloads:
            let activeItems = utilities.downloads.map { download in
                PersonalHubItem(
                    id: download.id,
                    title: download.name,
                    subtitle: [
                        download.percent.map { "\($0)%" },
                        download.isStalled ? "Stalled" : "Active",
                    ].compactMap { $0 }.joined(separator: " · "),
                    detail: "Downloading on the Mac",
                    symbol: "arrow.down.circle",
                    progress: download.progress,
                    actions: [
                        .init(id: "reveal", label: "Reveal on Mac", symbol: "folder", targetID: download.id)
                    ]
                )
            }
            let recentItems = utilities.recentDownloads.map { download in
                var actions: [PersonalHubAction] = [
                    .init(id: "reveal", label: "Reveal on Mac", symbol: "folder", targetID: download.id)
                ]
                if download.isTransferable {
                    actions.insert(
                        .init(
                            id: "downloadToDevice",
                            label: "Download",
                            symbol: "square.and.arrow.down",
                            role: .primary,
                            targetID: download.id
                        ),
                        at: 0
                    )
                }
                return PersonalHubItem(
                    id: download.id,
                    title: download.name,
                    subtitle: "Completed · \(Self.fileSize(download.bytes)) · \(Self.relativeDate(download.modifiedAt))",
                    detail: download.isTransferable
                        ? "Available to this paired device"
                        : "Over the 100 MB private transfer limit",
                    symbol: "checkmark.circle.fill",
                    actions: actions
                )
            }
            let summary: String
            if let download = utilities.primaryDownload {
                summary = download.percent.map { "\(download.name) · \($0)%" } ?? download.name
            } else if let completed = utilities.recentDownloadCompleted {
                summary = "Finished \(completed)"
            } else if !utilities.recentDownloads.isEmpty {
                summary = "\(utilities.recentDownloads.count) recent downloads"
            } else {
                summary = utilities.downloadsScanComplete ? "No active or recent downloads" : "Reading Downloads"
            }
            return .init(
                id: id,
                availability: utilities.downloadsScanComplete ? .ready : .loading,
                summary: summary,
                detail: "Active progress and the 12 most recent completed files from ~/Downloads",
                items: activeItems + recentItems,
                actions: [.init(id: "refresh", label: "Refresh", symbol: "arrow.clockwise")]
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
            let volume = data.quickSettings?.outputVolume
            return .init(
                id: id,
                availability: devices.isEmpty ? .loading : .ready,
                summary: active.isEmpty
                    ? ["\(devices.count) audio devices", volume.map { "Volume \($0)%" }].compactMap { $0 }.joined(separator: " · ")
                    : [active.map(\.name).joined(separator: " · "), volume.map { "Volume \($0)%" }].compactMap { $0 }.joined(separator: " · "),
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
                actions: [
                    .init(id: "volumeDown", label: "Volume −10", symbol: "speaker.minus"),
                    .init(id: "setVolume", label: "Set volume", symbol: "slider.horizontal.3", value: volume.map(String.init)),
                    .init(id: "volumeUp", label: "Volume +10", symbol: "speaker.plus"),
                    .init(id: "openSettings", label: "Open Sound Settings", symbol: "gearshape")
                ]
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
            let mirror = SystemNotificationMirror.makeSnapshot(
                candidates: Self.notificationCandidates(appState: appState),
                providerState: SystemNotificationMirror.currentProviderState
            )
            let count = mirror.actionRequired.count
            return .init(
                id: id,
                availability: .partial,
                summary: count == 0
                    ? "No CodeIsland alerts need attention"
                    : "\(count) CodeIsland alert\(count == 1 ? "" : "s") need attention",
                detail: mirror.providerState.message,
                items: mirror.actionRequired.map { alert in
                    .init(
                        id: alert.id,
                        title: alert.title,
                        subtitle: "\(alert.source) · Action required",
                        detail: alert.body,
                        symbol: alert.isRedacted ? "eye.slash.fill" : "exclamationmark.circle.fill"
                    )
                }
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
                summary: "Private camera and microphone pre-check",
                detail: "Preview and input levels stay on the device running the check. No media enters the remote snapshot.",
                actions: [
                    .init(id: "previewLocal", label: "Preview", symbol: "camera.fill", role: .primary)
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
            items.append(contentsOf: data.claudeProposals.map { proposal in
                let timing: String?
                switch proposal.kind {
                case .reminder:
                    timing = proposal.due.map { "Due \(Self.eventDate($0))" }
                case .calendar:
                    timing = proposal.start.map(Self.eventDate)
                case .note:
                    timing = nil
                }
                return .init(
                    id: "proposal:\(proposal.id)",
                    title: proposal.title,
                    subtitle: ["Claude proposal · \(proposal.summary)", timing].compactMap { $0 }.joined(separator: " · "),
                    detail: proposal.text ?? proposal.notes,
                    symbol: "checklist",
                    actions: [
                        .init(
                            id: "applyProposal",
                            label: "Review",
                            symbol: "checkmark.seal.fill",
                            role: .primary,
                            targetID: proposal.id
                        )
                    ]
                )
            })
            return .init(
                id: id,
                availability: data.claudeBusy ? .loading : .ready,
                summary: data.claudeBusy ? "Claude is working" : (data.claudeError ?? "Ask or prepare reviewed actions with your Claude Code login"),
                detail: "Ask is read-only. Do only creates proposals; every write still requires CodeIsland Review and confirmation.",
                items: items,
                actions: [
                    .init(id: "ask", label: "Ask", symbol: "sparkles"),
                    .init(id: "plan", label: "Do", symbol: "checklist", role: .primary)
                ]
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

    private func calendarItem(_ event: GlancesModel.EventInfo) -> PersonalHubItem {
        var actions: [PersonalHubAction] = []
        if let joinURL = event.joinURL {
            actions.append(.init(
                id: "join",
                label: "Join here",
                symbol: "video.fill",
                role: .primary,
                targetID: event.sourceID,
                deepLink: joinURL
            ))
            actions.append(.init(
                id: "openOnMac",
                label: "Open on Mac",
                symbol: "macbook",
                targetID: event.sourceID
            ))
        }
        if event.isEditable {
            let draft = PersonalHubCalendarDraft(
                title: event.title,
                start: event.start,
                end: event.end,
                joinURL: event.joinURL,
                notes: event.notes
            )
            actions.append(.init(
                id: "edit",
                label: "Edit",
                symbol: "square.and.pencil",
                targetID: event.sourceID,
                value: draft.encodedActionValue()
            ))
            actions.append(.init(
                id: "delete",
                label: "Delete",
                symbol: "trash",
                role: .destructive,
                targetID: event.sourceID
            ))
        }
        return .init(
            id: event.id,
            title: event.title,
            subtitle: "\(Self.eventTime(event)) · \(event.calendarTitle)",
            symbol: "calendar",
            date: event.start,
            actions: actions
        )
    }

    private static func agentAttentionLabel(_ status: AgentStatus) -> String {
        switch status {
        case .waitingApproval: return "Needs approval"
        case .waitingQuestion: return "Needs an answer"
        case .running: return "Running"
        case .processing: return "Processing"
        case .idle: return "Recent"
        }
    }

    private static func agentAttentionSymbol(_ status: AgentStatus) -> String {
        switch status {
        case .waitingApproval: return "checkmark.shield.fill"
        case .waitingQuestion: return "questionmark.bubble.fill"
        case .running, .processing: return "terminal.fill"
        case .idle: return "clock"
        }
    }

    private static func eventTime(_ event: GlancesModel.EventInfo) -> String {
        if event.isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.start)
    }

    private static func eventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func taskDue(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Due \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private static func taskCompleted(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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

    private static func fileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func shelfSourceLabel(_ value: String) -> String? {
        guard let source = ShelfCaptureController.Source(rawValue: value) else { return nil }
        switch source {
        case .clipboardFile: return "Clipboard"
        case .filePicker: return "File"
        case .drop: return "Dropped"
        case .automaticScreenshot: return "Screenshot"
        case .selection: return "Capture"
        case .recording: return "Recording"
        }
    }

    private static func notificationCandidates(appState: AppState) -> [SystemNotificationMirror.Entry] {
        let approvals = appState.permissionQueue.map { request in
            let tool = request.event.toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = request.event.toolDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SystemNotificationMirror.Entry(
                id: request.id,
                source: AppState.sourceLabel(for: request.event),
                title: tool.isEmpty ? "Approval required" : tool,
                body: description.isEmpty ? "A waiting agent needs your approval." : description,
                createdAt: request.createdAt,
                origin: .codeIslandAction,
                sessionID: request.event.sessionId ?? "default"
            )
        }
        let questions = appState.questionQueue.map { request in
            SystemNotificationMirror.Entry(
                id: request.id,
                source: AppState.sourceLabel(for: request.event),
                title: "Decision required",
                body: request.question.question,
                createdAt: request.createdAt,
                origin: .codeIslandAction,
                sessionID: request.event.sessionId ?? "default"
            )
        }
        return approvals + questions
    }

    private static func playbackTime(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h"
    }
}
