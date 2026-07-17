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

        case (.quickToggles, "lockMac"):
            let script = #"tell application "System Events" to keystroke "q" using {control down, command down}"#
            guard ProcessRunner.run(path: "/usr/bin/osascript", args: ["-e", script], timeout: 5) != nil else {
                return .failure(.failed("CodeIsland needs Accessibility access to lock the Mac"))
            }
            return .success(.init(executed: true, message: "Mac locked"))

        case (.reminders, "add"):
            guard let value = intent.value, glances.addReminder(title: value) else {
                return .failure(.failed(glances.reminderMutationError ?? "Could not add the task"))
            }
            return .success(.init(executed: true, message: "Task added"))

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            glances.complete(reminder)
            return .success(.init(executed: true, message: "Task completed"))

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.nextEvent,
                  event.id == targetID,
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

        case (.quickToggles, "lockMac"):
            return .success("Lock this Mac now")

        case (.reminders, "add"):
            let value = GlancesModel.normalizedReminderTitle(intent.value ?? "")
            guard glances.remindersAuthorized else {
                return .failure(.invalid("Reminders access is required on the Mac"))
            }
            guard !value.isEmpty else { return .failure(.invalid("Enter a task")) }
            guard value.count <= 500 else { return .failure(.invalid("Task is too long")) }
            return .success("Add “\(value)” to the selected Reminders list")

        case (.reminders, "complete"):
            guard let targetID = intent.targetID,
                  let reminder = glances.reminders.first(where: { $0.id == targetID })
            else { return .failure(.invalid("Task is no longer available")) }
            return .success("Mark “\(reminder.title)” complete")

        case (.calendar, "openOnMac"):
            guard let targetID = intent.targetID,
                  let event = glances.nextEvent,
                  event.id == targetID,
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
                            detail: media.album,
                            symbol: media.isPlaying ? "speaker.wave.2.fill" : "pause.fill"
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
            guard let event = glances.nextEvent else {
                return .init(id: id, availability: .partial, summary: "No upcoming events")
            }
            var actions: [PersonalHubAction] = []
            if let joinURL = event.joinURL {
                actions.append(.init(
                    id: "join",
                    label: "Join on iPhone",
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
            return .init(
                id: id,
                availability: .partial,
                summary: event.title,
                detail: Self.eventTime(event),
                items: [
                    .init(
                        id: event.id,
                        title: event.title,
                        subtitle: Self.eventTime(event),
                        symbol: "calendar",
                        actions: actions
                    )
                ]
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
                availability: .partial,
                summary: glances.reminders.isEmpty
                    ? "No open tasks in the selected lists"
                    : "\(glances.reminders.count) open",
                items: glances.reminders.map { reminder in
                    .init(
                        id: reminder.id,
                        title: reminder.title,
                        subtitle: reminder.due.map(Self.taskDue),
                        symbol: "circle",
                        actions: [
                            .init(
                                id: "complete",
                                label: "Complete",
                                symbol: "checkmark.circle.fill",
                                role: .primary,
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
                availability: .partial,
                summary: utilities.deviceBatteries.isEmpty
                    ? (utilities.bluetoothError ?? "No battery-capable devices")
                    : "\(utilities.deviceBatteries.count) devices",
                items: utilities.deviceBatteries.map { device in
                    .init(
                        id: device.id,
                        title: device.name,
                        subtitle: device.summary,
                        symbol: "antenna.radiowaves.left.and.right"
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
                    subtitle: "\(mac.percent)% · \(mac.status) · \(mac.powerSource)",
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
                availability: devices.isEmpty ? .loading : .partial,
                summary: active.isEmpty
                    ? "\(devices.count) audio devices"
                    : active.map(\.name).joined(separator: " · "),
                detail: "Device switching is pending; Sound Settings can be opened remotely",
                items: devices.prefix(12).map { device in
                    let roles = [
                        device.isDefaultInput ? "Default input" : nil,
                        device.isDefaultOutput ? "Default output" : nil,
                        device.isInput && !device.isDefaultInput ? "Input" : nil,
                        device.isOutput && !device.isDefaultOutput ? "Output" : nil,
                    ].compactMap { $0 }.joined(separator: " · ")
                    return .init(id: device.id, title: device.name, subtitle: roles, symbol: "speaker.wave.2")
                },
                actions: [.init(id: "openSettings", label: "Open Sound Settings", symbol: "slider.horizontal.3")]
            )

        case .quickToggles:
            return .init(
                id: id,
                availability: .partial,
                summary: "Lock this Mac from iPhone or web",
                actions: [
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
