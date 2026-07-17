import AppKit
import CodeIslandCore
import SwiftUI

/// Native Mac surface for the same hub contract used by Buddy and the private
/// web client. All local mutations still use prepare -> confirm -> execute so
/// the behavior cannot drift from remote safety semantics.
struct PersonalHubMacView: View {
    var appState: AppState

    @ObservedObject private var personalData = PersonalHubDataModel.shared

    @State private var requestedMode: PersonalHubMode = .auto
    @State private var snapshot: PersonalHubSnapshot?
    @State private var preparedAction: PersonalHubPreparedAction?
    @State private var actionMessage: String?
    @State private var showingRackEditor = false
    @State private var calendarReferenceDate = Date()
    @State private var calendarSelectedDate = Date()

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
                    Button {
                        toggleDashboard(snapshot)
                    } label: {
                        Image(systemName: snapshot.configuration?.dashboardEnabled == false
                            ? "gauge.with.dots.needle.0percent"
                            : "gauge.with.dots.needle.67percent")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.48))
                    .help(snapshot.configuration?.dashboardEnabled == false
                        ? "Show day dashboard"
                        : "Hide day dashboard")
                    Button {
                        showingRackEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .help("Edit \(snapshot.resolvedMode.rawValue.capitalized) rack")
                }
                .padding(.horizontal, 12)

                if snapshot.configuration?.dashboardEnabled != false,
                   let dayProgress = snapshot.dayProgress {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("DAY")
                            Spacer()
                            Text("\(Int((dayProgress * 100).rounded()))%")
                        }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.36))
                        ProgressView(value: dayProgress)
                            .tint(accent)
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 12)
                }

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(snapshot.modules) { module in
                            MacHubModuleCard(
                                module: module,
                                prepare: prepare,
                                addText: addText,
                                selectCalendarDate: selectCalendarDate
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
        .onReceive(personalData.$shelf) { _ in refresh() }
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
        .sheet(isPresented: $showingRackEditor) {
            if let snapshot,
               let configuration = snapshot.configuration {
                MacModeRackEditor(
                    mode: snapshot.resolvedMode,
                    modules: configuration.rack(for: snapshot.resolvedMode)
                ) { modules in
                    showingRackEditor = false
                    saveRack(mode: snapshot.resolvedMode, modules: modules)
                }
            }
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
        snapshot = service.snapshot(
            appState: appState,
            requestedMode: requestedMode,
            calendarReferenceDate: calendarReferenceDate,
            calendarSelectedDate: calendarSelectedDate
        )
    }

    private func selectCalendarDate(referenceDate: Date, selectedDate: Date) {
        calendarReferenceDate = referenceDate
        calendarSelectedDate = selectedDate
        refresh()
    }

    private func saveRack(mode: PersonalHubMode, modules: [PersonalHubModuleID]) {
        let mutation = PersonalHubConfigurationMutation(mode: mode, modules: modules)
        acceptPrepared(service.prepare(
            intent: .init(
                moduleID: .quickToggles,
                actionID: "setModeRack",
                value: mutation.encodedActionValue()
            ),
            deviceID: "local-mac"
        ))
    }

    private func toggleDashboard(_ snapshot: PersonalHubSnapshot) {
        let enabled = !(snapshot.configuration?.dashboardEnabled ?? true)
        let mutation = PersonalHubConfigurationMutation(dashboardEnabled: enabled)
        acceptPrepared(service.prepare(
            intent: .init(
                moduleID: .quickToggles,
                actionID: "setDashboard",
                value: mutation.encodedActionValue()
            ),
            deviceID: "local-mac"
        ))
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
        if action.id == "downloadToDevice", let itemID,
           let fileURL = service.shelfFileURL(id: itemID) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            return
        }
        if moduleID == .camera, action.id == "previewOnDevice" {
            let photoBooth = URL(fileURLWithPath: "/System/Applications/Photo Booth.app")
            NSWorkspace.shared.open(photoBooth)
            return
        }
        if moduleID == .notes, ["append", "replace"].contains(action.id), let itemID {
            let seed = PersonalHubNoteDraft.decodeActionValue(action.value)
            guard let value = promptForNote(
                title: action.id == "append" ? "Append to note" : "Edit note",
                initialValue: action.id == "replace" ? (seed?.text ?? itemDetail ?? "") : ""
            ) else { return }
            let actionValue = action.id == "replace"
                ? PersonalHubNoteDraft(
                    text: value,
                    category: seed?.category,
                    baseRevision: seed?.baseRevision
                ).encodedActionValue()
                : value
            acceptPrepared(service.prepare(
                intent: .init(moduleID: .notes, actionID: action.id, targetID: itemID, value: actionValue),
                deviceID: "local-mac"
            ))
            return
        }
        if moduleID == .notes,
           action.id == "setCategory",
           let itemID,
           let seed = PersonalHubNoteDraft.decodeActionValue(action.value),
           let category = promptForCategory(initial: seed.category ?? "") {
            let updated = PersonalHubNoteDraft(
                text: seed.text,
                category: category,
                baseRevision: seed.baseRevision
            )
            acceptPrepared(service.prepare(
                intent: .init(
                    moduleID: .notes,
                    actionID: "setCategory",
                    targetID: itemID,
                    value: updated.encodedActionValue()
                ),
                deviceID: "local-mac"
            ))
            return
        }
        if moduleID == .calendar,
           action.id == "edit",
           let itemID,
           let draft = PersonalHubCalendarDraft.decodeActionValue(action.value),
           let updated = promptForCalendar(draft) {
            acceptPrepared(service.prepare(
                intent: .init(
                    moduleID: .calendar,
                    actionID: "edit",
                    targetID: itemID,
                    value: updated.encodedActionValue()
                ),
                deviceID: "local-mac"
            ))
            return
        }
        if moduleID == .audio, action.id == "setVolume",
           let volume = promptForVolume(initial: Int(action.value ?? "") ?? 50) {
            acceptPrepared(service.prepare(
                intent: .init(moduleID: .audio, actionID: "setVolume", value: String(volume)),
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
            targetID: action.targetID ?? itemID,
            value: action.value
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

    private func promptForCategory(initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Set note category"
        alert.informativeText = "Leave blank to clear it."
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: initial)
        field.placeholderString = "Work, Home, Ideas…"
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 28)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return String(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private func promptForCalendar(_ draft: PersonalHubCalendarDraft) -> PersonalHubCalendarDraft? {
        let alert = NSAlert()
        alert.messageText = "Edit event"
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        let titleField = NSTextField(string: draft.title)
        titleField.placeholderString = "Event title"
        let startPicker = NSDatePicker()
        startPicker.datePickerElements = [.yearMonthDay, .hourMinute]
        startPicker.dateValue = draft.start
        let endPicker = NSDatePicker()
        endPicker.datePickerElements = [.yearMonthDay, .hourMinute]
        endPicker.dateValue = draft.end
        let linkField = NSTextField(string: draft.joinURL?.absoluteString ?? "")
        linkField.placeholderString = "Meeting link (optional)"
        let notesField = NSTextField(string: draft.notes ?? "")
        notesField.placeholderString = "Notes (optional)"

        for view in [titleField, startPicker, endPicker, linkField, notesField] {
            view.widthAnchor.constraint(equalToConstant: 440).isActive = true
            stack.addArrangedSubview(view)
        }
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = linkField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = link.isEmpty ? nil : URL(string: link)
        guard !title.isEmpty, endPicker.dateValue > startPicker.dateValue, link.isEmpty || url != nil else {
            actionMessage = "Enter a title, valid time range, and valid meeting URL"
            return nil
        }
        return .init(
            title: title,
            start: startPicker.dateValue,
            end: endPicker.dateValue,
            joinURL: url,
            notes: notesField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func promptForVolume(initial: Int) -> Int? {
        let alert = NSAlert()
        alert.messageText = "Set Mac output volume"
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        let slider = NSSlider(
            value: Double(min(max(initial, 0), 100)),
            minValue: 0,
            maxValue: 100,
            target: nil,
            action: nil
        )
        slider.numberOfTickMarks = 11
        slider.allowsTickMarkValuesOnly = false
        slider.frame = NSRect(x: 0, y: 0, width: 360, height: 34)
        alert.accessoryView = slider
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return Int(slider.doubleValue.rounded())
    }
}

private struct MacHubModuleCard: View {
    let module: PersonalHubModuleSnapshot
    let prepare: (PersonalHubModuleID, PersonalHubAction, String?, String?) -> Void
    let addText: (PersonalHubModuleID, String, String) -> Void
    let selectCalendarDate: (Date, Date) -> Void

    @State private var showsTaskComposer = false
    @State private var taskTitle = ""
    @State private var eventStart = Date().addingTimeInterval(3_600)
    @State private var eventEnd = Date().addingTimeInterval(7_200)
    @State private var composerActionID = "add"
    @State private var selectedReminderCalendarID = ""
    @State private var mediaSeekPosition = 0.0
    @State private var isMediaSeeking = false

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

            if let detail = module.detail {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: module.id == .notifications ? "eye.slash" : "info.circle")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(module.id == .notifications ? Color.orange : Color.white.opacity(0.34))
                    Text(detail)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
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
                        composerTextField(prompt: composerActionID == "plan" ? "Tell Claude what to do" : "Ask Claude")
                        reviewButton(
                            actionID: composerActionID,
                            value: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } else if module.id == .reminders, composerActionID == "addList" {
                    HStack(spacing: 5) {
                        composerTextField(prompt: "New list name")
                        reviewButton(
                            actionID: "addList",
                            value: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                } else {
                    HStack(spacing: 5) {
                        composerTextField(prompt: module.id == .notes ? "New note" : "New task")
                        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if module.id == .reminders, !reminderLists.isEmpty {
                            Picker("", selection: $selectedReminderCalendarID) {
                                ForEach(reminderLists) { list in
                                    Text(list.title).tag(list.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 110)
                        }
                        reviewButton(value: module.id == .reminders
                            ? PersonalHubReminderDraft(
                                title: title,
                                calendarID: selectedReminderCalendarID.isEmpty ? nil : selectedReminderCalendarID
                            ).encodedActionValue()
                            : title)
                    }
                }
            }

            if module.id == .shelf {
                MacShelfCaptureControls()
            }

            if let month = module.calendarMonth {
                MacCalendarMonthView(month: month, onSelection: selectCalendarDate)
                Text(month.selectedEvents.isEmpty ? "NO EVENTS" : "SELECTED DAY")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.28))
                ForEach(month.selectedEvents) { item in
                    itemCard(item)
                }
                if !module.items.isEmpty {
                    Text("UPCOMING")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.28))
                }
            }

            ForEach(module.calendarMonth == nil ? module.items : Array(module.items.prefix(6))) { item in
                itemCard(item)
            }

            actionRow(module.actions, itemID: nil, itemDetail: nil)
        }
        .padding(8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .onAppear {
            if selectedReminderCalendarID.isEmpty {
                selectedReminderCalendarID = reminderLists.first?.id ?? ""
            }
        }
    }

    private func itemCard(_ item: PersonalHubItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 7) {
                if let data = item.decodedArtworkJPEG, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            if let progress = item.progress {
                ProgressView(value: progress).tint(.orange)
            }
            if let duration = item.mediaDuration, duration.isFinite, duration > 0 {
                Slider(
                    value: $mediaSeekPosition,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isMediaSeeking = editing
                        guard !editing else { return }
                        prepare(
                            module.id,
                            .init(
                                id: "seek",
                                label: "Seek",
                                symbol: "slider.horizontal.3",
                                value: String(mediaSeekPosition)
                            ),
                            item.id,
                            item.detail
                        )
                    }
                )
                .tint(.orange)
                .controlSize(.mini)
                .accessibilityLabel("Playback position")
                HStack {
                    Text(playbackTime(mediaSeekPosition))
                    Spacer()
                    Text(playbackTime(duration))
                }
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .onAppear {
                    mediaSeekPosition = min(max(item.mediaPosition ?? 0, 0), duration)
                }
                .onChange(of: item.mediaPosition) { _, position in
                    guard !isMediaSeeking else { return }
                    mediaSeekPosition = min(max(position ?? 0, 0), duration)
                }
            }
            actionRow(item.actions, itemID: item.id, itemDetail: item.detail)
        }
        .padding(6)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func actionRow(
        _ actions: [PersonalHubAction],
        itemID: String?,
        itemDetail: String?
    ) -> some View {
        if !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(actions) { action in
                        Button {
                        if ([.calendar, .reminders, .notes].contains(module.id) && action.id == "add")
                            || (module.id == .reminders && action.id == "addList")
                            || (module.id == .teleprompter && action.id == "set")
                            || (module.id == .claude && ["ask", "plan"].contains(action.id)) {
                            composerActionID = action.id
                            taskTitle = ""
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

    private var reminderLists: [MacReminderListChoice] {
        module.items.compactMap { item in
            guard item.id.hasPrefix("list:"), let id = item.detail else { return nil }
            return .init(id: id, title: item.title)
        }
    }

    private func playbackTime(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct MacShelfCaptureControls: View {
    @ObservedObject private var capture = PersonalHubDataModel.shared.shelfCaptureController
    @State private var isDropTarget = false

    private let data = PersonalHubDataModel.shared
    private let accent = Color(red: 1.0, green: 0.69, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                captureButton("Add", symbol: "plus") { chooseFiles() }
                captureButton("Clipboard", symbol: "doc.on.clipboard") {
                    _ = data.captureClipboardNow()
                }
                captureButton("Capture", symbol: "viewfinder") {
                    capture.presentSelectionCapture()
                }
                captureButton(
                    capture.isRecording ? "Stop" : "Record",
                    symbol: capture.isRecording ? "stop.fill" : "record.circle"
                ) {
                    if capture.isRecording {
                        capture.stopRecording()
                    } else {
                        capture.presentRecordingCapture()
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: isDropTarget ? "arrow.down.doc.fill" : "arrow.down.doc")
                Text(isDropTarget ? "RELEASE TO ADD" : "DROP FILES INTO SHELF")
            }
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .foregroundStyle(isDropTarget ? .black : .white.opacity(0.36))
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                isDropTarget ? accent : Color.white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isDropTarget ? accent : Color.white.opacity(0.08), lineWidth: 1)
            )
            .dropDestination(for: URL.self) { urls, _ in
                urls.reduce(false) { imported, url in
                    data.importShelfFile(at: url, source: .drop) || imported
                }
            } isTargeted: { targeted in
                isDropTarget = targeted
            }

            if capture.isPresentingPicker {
                Text("Choose a window, app, or display in the system picker")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.38))
            } else if capture.isRecording {
                Text("Recording selected content · Stop when finished")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent)
            } else if let error = capture.lastError {
                Text(error)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.82))
            }
        }
        .padding(7)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func captureButton(
        _ label: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(label == "Stop" ? Color.red.opacity(0.9) : .white.opacity(0.66))
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = "Add to Shelf"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            _ = data.importShelfFile(at: url, source: .filePicker)
        }
    }
}

struct MacCalendarMonthView: View {
    let month: PersonalHubCalendarMonth
    let onSelection: (Date, Date) -> Void

    private let calendar = Calendar.current
    private let accent = Color(red: 1.0, green: 0.69, blue: 0.0)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Button { moveMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous month")
                Spacer()
                Text(month.displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Button("Today") { onSelection(Date(), Date()) }
                    .font(.system(size: 8, weight: .bold))
                    .help("Show today")
                Button { moveMonth(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next month")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(accent)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.26))
                        .frame(maxWidth: .infinity)
                }
                ForEach(month.days) { day in
                    Button {
                        onSelection(month.displayedMonth, day.date)
                    } label: {
                        VStack(spacing: 1) {
                            Text("\(calendar.component(.day, from: day.date))")
                                .font(.system(size: 9, weight: isSelected(day) ? .bold : .medium, design: .rounded))
                            HStack(spacing: 1) {
                                ForEach(0..<min(day.eventCount, 3), id: \.self) { _ in
                                    Circle().frame(width: 2, height: 2)
                                }
                            }
                            .frame(height: 3)
                        }
                        .foregroundStyle(day.isInDisplayedMonth ? .white.opacity(0.82) : .white.opacity(0.2))
                        .frame(maxWidth: .infinity, minHeight: 25)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected(day) ? accent.opacity(0.26) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(day.isToday ? accent.opacity(0.9) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(day.eventCount == 1 ? "1 event" : "\(day.eventCount) events")
                }
            }
        }
        .padding(7)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func isSelected(_ day: PersonalHubCalendarDay) -> Bool {
        calendar.isDate(day.date, inSameDayAs: month.selectedDate)
    }

    private func moveMonth(_ offset: Int) {
        guard let reference = calendar.date(byAdding: .month, value: offset, to: month.displayedMonth) else { return }
        onSelection(reference, reference)
    }
}

private struct MacReminderListChoice: Identifiable {
    let id: String
    let title: String
}

private struct MacModeRackEditor: View {
    let mode: PersonalHubMode
    let onSave: ([PersonalHubModuleID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var modules: [PersonalHubModuleID]

    init(
        mode: PersonalHubMode,
        modules: [PersonalHubModuleID],
        onSave: @escaping ([PersonalHubModuleID]) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        _modules = State(initialValue: modules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(mode.rawValue.capitalized) rack")
                        .font(.system(size: 17, weight: .bold))
                    Text("Choose the modules and order shared by Mac, iPhone, and web.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Review") { onSave(modules) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(modules.isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PINNED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                        HStack(spacing: 9) {
                            Label(
                                PersonalHubCatalog.definition(for: module).title,
                                systemImage: PersonalHubCatalog.definition(for: module).symbol
                            )
                            .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button { move(index, by: -1) } label: {
                                Image(systemName: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button { move(index, by: 1) } label: {
                                Image(systemName: "arrow.down")
                            }
                            .disabled(index == modules.count - 1)
                            Button { modules.remove(at: index) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .disabled(modules.count == 1)
                        }
                        .buttonStyle(.borderless)
                        .padding(9)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !availableModules.isEmpty {
                        Text("AVAILABLE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 7)

                        ForEach(availableModules) { module in
                            HStack {
                                Label(
                                    PersonalHubCatalog.definition(for: module).title,
                                    systemImage: PersonalHubCatalog.definition(for: module).symbol
                                )
                                .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Button { modules.append(module) } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(9)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 500, height: 560)
    }

    private var availableModules: [PersonalHubModuleID] {
        PersonalHubModuleID.allCases.filter { !modules.contains($0) }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }
        modules.swapAt(index, destination)
    }
}
