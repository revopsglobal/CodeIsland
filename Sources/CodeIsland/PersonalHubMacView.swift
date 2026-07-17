import AppKit
import CodeIslandCore
import SwiftUI

/// Native Mac surface for the same hub contract used by Buddy and the private
/// web client. All local mutations still use prepare -> confirm -> execute so
/// the behavior cannot drift from remote safety semantics.
struct PersonalHubMacView: View {
    var appState: AppState

    @State private var requestedMode: PersonalHubMode = .auto
    @State private var snapshot: PersonalHubSnapshot?
    @State private var preparedAction: PersonalHubPreparedAction?
    @State private var actionMessage: String?

    private let service = PersonalHubService.shared
    private let accent = Color(red: 1.0, green: 0.69, blue: 0.0)

    var body: some View {
        VStack(spacing: 8) {
            modeStrip

            if let snapshot {
                HStack {
                    Text(snapshot.resolvedMode.rawValue.uppercased())
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                    Text(snapshot.serverName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.34))
                    Spacer()
                    Text(snapshot.generatedAt, style: .time)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.horizontal, 12)

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(snapshot.modules) { module in
                            MacHubModuleCard(
                                module: module,
                                prepare: prepare,
                                addText: addText
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .frame(maxHeight: 410)
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
        }
        .task {
            refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                refresh()
            }
        }
        .onChange(of: requestedMode) { _, _ in refresh() }
        .confirmationDialog(
            "Review action",
            isPresented: Binding(
                get: { preparedAction != nil },
                set: { if !$0 { preparedAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: preparedAction
        ) { prepared in
            Button("Do it") { execute(prepared) }
            Button("Cancel", role: .cancel) { preparedAction = nil }
        } message: { prepared in
            Text(prepared.preview)
        }
    }

    private var modeStrip: some View {
        HStack(spacing: 3) {
            ForEach(PersonalHubMode.allCases) { mode in
                Button {
                    requestedMode = mode
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(requestedMode == mode ? .black : .white.opacity(0.38))
                        .frame(maxWidth: .infinity, minHeight: 25)
                        .background(
                            requestedMode == mode ? accent : Color.white.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func refresh() {
        snapshot = service.snapshot(appState: appState, requestedMode: requestedMode)
    }

    private func prepare(
        moduleID: PersonalHubModuleID,
        action: PersonalHubAction,
        itemID: String?,
        itemDetail: String?
    ) {
        if action.id == "copyToDevice", let itemDetail {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(itemDetail, forType: .string) {
                actionMessage = "Copied to this Mac"
            }
            return
        }
        if action.id == "presentOnDevice", let itemDetail {
            TeleprompterWindowController.shared.show(text: itemDetail)
            return
        }
        if moduleID == .camera, action.id == "previewOnDevice" {
            let photoBooth = URL(fileURLWithPath: "/System/Applications/Photo Booth.app")
            NSWorkspace.shared.open(photoBooth)
            return
        }
        if moduleID == .notes, ["append", "replace"].contains(action.id), let itemID {
            guard let value = promptForNote(
                title: action.id == "append" ? "Append to note" : "Edit note",
                initialValue: action.id == "replace" ? (itemDetail ?? "") : ""
            ) else { return }
            acceptPrepared(service.prepare(
                intent: .init(moduleID: .notes, actionID: action.id, targetID: itemID, value: value),
                deviceID: "local-mac"
            ))
            return
        }
        if let deepLink = action.deepLink {
            NSWorkspace.shared.open(deepLink)
            return
        }
        let intent = PersonalHubActionIntent(
            moduleID: moduleID,
            actionID: action.id,
            targetID: action.targetID ?? itemID
        )
        acceptPrepared(service.prepare(intent: intent, deviceID: "local-mac"))
    }

    private func addText(moduleID: PersonalHubModuleID, actionID: String, value: String) {
        acceptPrepared(service.prepare(
            intent: .init(moduleID: moduleID, actionID: actionID, value: value),
            deviceID: "local-mac"
        ))
    }

    private func acceptPrepared(_ result: Result<PersonalHubPreparedAction, PersonalHubService.ActionError>) {
        switch result {
        case .success(let prepared):
            preparedAction = prepared
            actionMessage = nil
        case .failure(let error):
            actionMessage = error.localizedDescription
        }
    }

    private func execute(_ prepared: PersonalHubPreparedAction) {
        let result = service.execute(
            request: .init(intent: prepared.intent, actionToken: prepared.actionToken),
            deviceID: "local-mac"
        )
        preparedAction = nil
        switch result {
        case .success(let response):
            actionMessage = response.message
            refresh()
        case .failure(let error):
            actionMessage = error.localizedDescription
        }
    }

    private func promptForNote(title: String, initialValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 170))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = initialValue
        scrollView.documentView = textView
        alert.accessoryView = scrollView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct MacHubModuleCard: View {
    let module: PersonalHubModuleSnapshot
    let prepare: (PersonalHubModuleID, PersonalHubAction, String?, String?) -> Void
    let addText: (PersonalHubModuleID, String, String) -> Void

    @State private var showsTaskComposer = false
    @State private var taskTitle = ""
    @State private var eventStart = Date().addingTimeInterval(3_600)
    @State private var eventEnd = Date().addingTimeInterval(7_200)

    private var definition: PersonalHubModuleDefinition {
        PersonalHubCatalog.definition(for: module.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: definition.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(definition.title)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.86))
                    Text(module.summary)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                availability
            }

            if showsTaskComposer {
                if module.id == .calendar {
                    VStack(alignment: .leading, spacing: 5) {
                        composerTextField(prompt: "Event title")
                        DatePicker("Starts", selection: $eventStart, in: Date()...)
                            .datePickerStyle(.compact)
                            .font(.system(size: 9, weight: .medium))
                        DatePicker("Ends", selection: $eventEnd, in: eventStart...)
                            .datePickerStyle(.compact)
                            .font(.system(size: 9, weight: .medium))
                        reviewButton(value: PersonalHubCalendarDraft(
                            title: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                            start: eventStart,
                            end: eventEnd
                        ).encodedActionValue())
                    }
                } else if module.id == .teleprompter {
                    VStack(alignment: .leading, spacing: 5) {
                        TextEditor(text: $taskTitle)
                            .font(.system(size: 10, weight: .medium))
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(5)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        reviewButton(
                            actionID: "set",
                            value: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } else if module.id == .claude {
                    HStack(spacing: 5) {
                        composerTextField(prompt: "Ask Claude")
                        reviewButton(
                            actionID: "ask",
                            value: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } else {
                    HStack(spacing: 5) {
                        composerTextField(prompt: module.id == .notes ? "New note" : "New task")
                        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        reviewButton(value: module.id == .reminders
                            ? PersonalHubReminderDraft(title: title).encodedActionValue()
                            : title)
                    }
                }
            }

            ForEach(module.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                        Spacer()
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    if let progress = item.progress {
                        ProgressView(value: progress).tint(.orange)
                    }
                    actionRow(item.actions, itemID: item.id, itemDetail: item.detail)
                }
                .padding(6)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
            }

            actionRow(module.actions, itemID: nil, itemDetail: nil)
        }
        .padding(8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder
    private func actionRow(
        _ actions: [PersonalHubAction],
        itemID: String?,
        itemDetail: String?
    ) -> some View {
        if !actions.isEmpty {
            HStack(spacing: 5) {
                ForEach(actions) { action in
                    Button {
                        if ([.calendar, .reminders, .notes].contains(module.id) && action.id == "add")
                            || (module.id == .teleprompter && action.id == "set")
                            || (module.id == .claude && action.id == "ask") {
                            showsTaskComposer.toggle()
                        } else {
                            prepare(module.id, action, itemID, itemDetail)
                        }
                    } label: {
                        Label(action.label, systemImage: action.symbol ?? "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }

    @ViewBuilder
    private var availability: some View {
        switch module.availability {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange)
        case .partial:
            Text("PARTIAL").foregroundStyle(.orange)
        case .loading:
            ProgressView().controlSize(.mini)
        case .permissionRequired:
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
        case .offline:
            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
        case .unavailable:
            Text("NEXT").foregroundStyle(.white.opacity(0.25))
        }
    }

    private func composerTextField(prompt: String) -> some View {
        TextField(prompt, text: $taskTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .padding(6)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private func reviewButton(actionID: String = "add", value: String?) -> some View {
        Button("Review") {
            guard let value,
                  !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            addText(module.id, actionID, value)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.small)
        .disabled(value == nil || taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
