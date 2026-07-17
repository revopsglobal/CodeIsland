import SwiftUI
import UIKit
import AVFoundation
import Speech

private enum HubTheme {
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.0)
    static let foreground = Color.white
    static let surface = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.09)
}

struct PersonalHubSurface: View {
    @EnvironmentObject private var client: RemoteApprovalClient

    var body: some View {
        VStack(spacing: 10) {
            modeStrip

            if let snapshot = client.hubSnapshot {
                HStack(spacing: 8) {
                    Text(snapshot.resolvedMode.displayTitle)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(HubTheme.accent)
                    Text(snapshot.serverName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HubTheme.foreground.opacity(0.48))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(snapshot.generatedAt, style: .time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(HubTheme.foreground.opacity(0.34))
                }
                .padding(.horizontal, 4)

                LazyVStack(spacing: 9) {
                    ForEach(snapshot.modules) { module in
                        PersonalHubModuleCard(module: module)
                    }
                }
            } else if client.state == .unpaired {
                hubEmptyState(
                    symbol: "iphone.and.arrow.forward",
                    title: "Pair with your Mac",
                    detail: "Use the six-digit code in CodeIsland Settings → Buddy."
                )
            } else if let error = client.hubError {
                hubEmptyState(
                    symbol: "wifi.exclamationmark",
                    title: "Personal hub unavailable",
                    detail: error
                )
            } else {
                hubEmptyState(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Loading your Mac",
                    detail: "Fetching the selected mode over Tailscale."
                )
            }

        }
        .padding(10)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HubTheme.border, lineWidth: 1)
        )
        .task { await client.refreshHub() }
        .sheet(item: $client.preparedAction) { prepared in
            PersonalHubConfirmationSheet(prepared: prepared)
                .environmentObject(client)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("hub.surface")
    }

    private var modeStrip: some View {
        HStack(spacing: 5) {
            ForEach(PersonalHubMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        client.selectedMode = mode
                    }
                } label: {
                    Text(mode.displayTitle)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            client.selectedMode == mode ? Color.black : HubTheme.foreground.opacity(0.58)
                        )
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            client.selectedMode == mode ? HubTheme.accent : HubTheme.surface,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hub.mode.\(mode.rawValue)")
            }
        }
    }

    private func hubEmptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(HubTheme.accent)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(HubTheme.foreground.opacity(0.86))
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubTheme.foreground.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

private struct PersonalHubModuleCard: View {
    let module: PersonalHubModuleSnapshot
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.openURL) private var openURL
    @State private var composerText = ""
    @State private var showsComposer = false
    @State private var composerActionID = "add"
    @State private var eventStart = Date().addingTimeInterval(3_600)
    @State private var eventEnd = Date().addingTimeInterval(7_200)
    @State private var meetingLink = ""
    @State private var reminderHasDue = false
    @State private var reminderDue = Date().addingTimeInterval(3_600)
    @State private var selectedReminderCalendarID = ""
    @State private var outputVolume = 50.0
    @State private var showsCameraPreview = false
    @StateObject private var speech = HubSpeechRecognizer()

    private var definition: PersonalHubModuleDefinition {
        PersonalHubCatalog.definition(for: module.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: definition.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HubTheme.accent)
                    .frame(width: 24, height: 24)
                    .background(HubTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(HubTheme.foreground.opacity(0.9))
                    Text(module.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HubTheme.foreground.opacity(0.5))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)
                availabilityMark
            }

            if let detail = module.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(HubTheme.foreground.opacity(0.38))
            }

            if showsComposer {
                composer
            }

            if !module.items.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(module.items) { item in
                        PersonalHubItemRow(moduleID: module.id, item: item)
                        if item.id != module.items.last?.id {
                            Divider().overlay(Color.white.opacity(0.06))
                        }
                    }
                }
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
            }

            if !module.actions.isEmpty {
                HStack(spacing: 7) {
                    ForEach(module.actions) { action in
                        Button {
                            if ([.calendar, .reminders, .notes].contains(module.id) && action.id == "add")
                                || (module.id == .reminders && action.id == "addList")
                                || (module.id == .audio && action.id == "setVolume")
                                || (module.id == .teleprompter && action.id == "set")
                                || (module.id == .claude && ["ask", "plan"].contains(action.id)) {
                                composerActionID = action.id
                                composerText = ""
                                if module.id == .audio {
                                    outputVolume = Double(action.value ?? "") ?? 50
                                }
                                withAnimation(.easeOut(duration: 0.16)) { showsComposer.toggle() }
                            } else {
                                prepare(action)
                            }
                        } label: {
                            Label(action.label, systemImage: action.symbol ?? "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(HubSecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(11)
        .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubTheme.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.module.\(module.id.rawValue)")
        .fullScreenCover(isPresented: $showsCameraPreview) {
            CameraPreviewScreen()
        }
        .onAppear {
            if selectedReminderCalendarID.isEmpty {
                selectedReminderCalendarID = reminderLists.first?.id ?? ""
            }
        }
    }

    @ViewBuilder
    private var availabilityMark: some View {
        switch module.availability {
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(HubTheme.accent)
        case .partial:
            Text("PARTIAL")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(HubTheme.accent)
        case .loading:
            ProgressView().controlSize(.small).tint(HubTheme.accent)
        case .permissionRequired:
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
        case .offline:
            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
        case .unavailable:
            Text("NEXT")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(HubTheme.foreground.opacity(0.3))
        }
    }

    private func prepare(_ action: PersonalHubAction) {
        if module.id == .camera, action.id == "previewOnDevice" {
            showsCameraPreview = true
            return
        }
        if let deepLink = action.deepLink {
            openURL(deepLink)
            return
        }
        Task {
            await client.prepareHubAction(.init(
                moduleID: module.id,
                actionID: action.id,
                targetID: action.targetID,
                value: action.value
            ))
        }
    }

    @ViewBuilder
    private var composer: some View {
        if module.id == .calendar {
            VStack(alignment: .leading, spacing: 8) {
                hubTextField("Event title", text: $composerText)
                DatePicker("Starts", selection: $eventStart, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .font(.system(size: 11, weight: .semibold))
                DatePicker("Ends", selection: $eventEnd, in: eventStart..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .font(.system(size: 11, weight: .semibold))
                hubTextField("Meeting link (optional)", text: $meetingLink)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                reviewButton(value: calendarActionValue)
            }
        } else if module.id == .reminders {
            if composerActionID == "addList" {
                HStack(spacing: 7) {
                    hubTextField("New list name", text: $composerText)
                    reviewButton(actionID: "addList", value: composerText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    hubTextField("New task", text: $composerText)
                    if !reminderLists.isEmpty {
                        Picker("List", selection: $selectedReminderCalendarID) {
                            ForEach(reminderLists) { list in
                                Text(list.title).tag(list.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 11, weight: .semibold))
                    }
                    Toggle("Set due date", isOn: $reminderHasDue)
                        .font(.system(size: 11, weight: .semibold))
                    if reminderHasDue {
                        DatePicker("Due", selection: $reminderDue, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    reviewButton(value: PersonalHubReminderDraft(
                        title: composerText.trimmingCharacters(in: .whitespacesAndNewlines),
                        due: reminderHasDue ? reminderDue : nil,
                        calendarID: selectedReminderCalendarID.isEmpty ? nil : selectedReminderCalendarID
                    ).encodedActionValue())
                }
            }
        } else if module.id == .teleprompter {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $composerText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HubTheme.foreground)
                    .frame(minHeight: 110)
                    .padding(7)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                reviewButton(
                    actionID: "set",
                    value: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } else if module.id == .audio, composerActionID == "setVolume" {
            VStack(alignment: .leading, spacing: 8) {
                Text("Output volume \(Int(outputVolume.rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                Slider(value: $outputVolume, in: 0...100, step: 1)
                    .tint(HubTheme.accent)
                reviewButton(
                    actionID: "setVolume",
                    value: String(Int(outputVolume.rounded())),
                    requiresText: false
                )
            }
        } else if module.id == .claude {
            HStack(spacing: 7) {
                hubTextField(composerActionID == "plan" ? "Tell Claude what to do" : "Ask Claude", text: $composerText)
                Button {
                    speech.toggle { transcript in composerText = transcript }
                } label: {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(HubSecondaryButtonStyle())
                .accessibilityLabel(speech.isRecording ? "Stop voice input" : "Start voice input")
                reviewButton(
                    actionID: composerActionID,
                    value: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } else {
            HStack(spacing: 7) {
                hubTextField("New note", text: $composerText)
                reviewButton(value: composerText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func hubTextField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HubTheme.foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("hub.\(module.id.rawValue).composer")
    }

    private func reviewButton(
        actionID: String = "add",
        value: String?,
        requiresText: Bool = true
    ) -> some View {
        Button("Review") {
            guard let value,
                  !requiresText || !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task {
                await client.prepareHubAction(.init(
                    moduleID: module.id,
                    actionID: actionID,
                    value: value
                ))
            }
        }
        .buttonStyle(HubPrimaryButtonStyle())
        .disabled((requiresText && composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || value == nil)
    }

    private var calendarActionValue: String? {
        let trimmedLink = meetingLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmedLink.isEmpty ? nil : URL(string: trimmedLink)
        guard trimmedLink.isEmpty || url != nil else { return nil }
        return PersonalHubCalendarDraft(
            title: composerText.trimmingCharacters(in: .whitespacesAndNewlines),
            start: eventStart,
            end: eventEnd,
            joinURL: url
        ).encodedActionValue()
    }

    private var reminderLists: [ReminderListChoice] {
        module.items.compactMap { item in
            guard item.id.hasPrefix("list:"), let id = item.detail else { return nil }
            return ReminderListChoice(id: id, title: item.title)
        }
    }
}

@MainActor
private final class HubSpeechRecognizer: ObservableObject {
    @Published private(set) var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggle(onTranscript: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            Task { await start(onTranscript: onTranscript) }
        }
    }

    private func start(onTranscript: @escaping (String) -> Void) async {
        let speechAuthorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard speechAuthorization == .authorized, microphoneAllowed, recognizer?.isAvailable == true else { return }

        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition == true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        onTranscript(result.bestTranscription.formattedString)
                    }
                    if result?.isFinal == true || error != nil {
                        self?.stop()
                    }
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct ReminderListChoice: Identifiable {
    let id: String
    let title: String
}

private struct PersonalHubItemRow: View {
    let moduleID: PersonalHubModuleID
    let item: PersonalHubItem
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.openURL) private var openURL
    @State private var showsTeleprompter = false
    @State private var noteMutation: NoteMutation?
    @State private var calendarMutation: CalendarMutation?
    @State private var sharedFile: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HubTheme.foreground.opacity(0.42))
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HubTheme.foreground.opacity(0.84))
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(HubTheme.foreground.opacity(0.42))
                    }
                }
                Spacer(minLength: 4)
            }

            if let progress = item.progress {
                ProgressView(value: progress).tint(HubTheme.accent)
            }

            if !item.actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.actions) { action in
                            Button {
                            if action.id == "downloadToDevice" {
                                Task {
                                    if let url = await client.downloadShelfFile(id: item.id, filename: item.title) {
                                        sharedFile = SharedFile(url: url)
                                    }
                                }
                            } else if moduleID == .notes, ["append", "replace", "setCategory"].contains(action.id) {
                                let seed = PersonalHubNoteDraft.decodeActionValue(action.value)
                                noteMutation = .init(
                                    actionID: action.id,
                                    targetID: action.targetID ?? item.id,
                                    initialText: action.id == "replace"
                                        ? (seed?.text ?? item.detail ?? "")
                                        : (action.id == "setCategory" ? (seed?.category ?? "") : ""),
                                    seed: seed
                                )
                            } else if moduleID == .calendar,
                                      action.id == "edit",
                                      let draft = PersonalHubCalendarDraft.decodeActionValue(action.value) {
                                calendarMutation = .init(targetID: action.targetID ?? item.id, draft: draft)
                            } else if action.id == "presentOnDevice", item.detail != nil {
                                showsTeleprompter = true
                            } else if action.id == "copyToDevice", let value = item.detail {
                                UIPasteboard.general.string = value
                                client.reportHubClientAction("Copied to iPhone")
                            } else if let deepLink = action.deepLink {
                                openURL(deepLink)
                            } else {
                                Task {
                                    await client.prepareHubAction(.init(
                                        moduleID: moduleID,
                                        actionID: action.id,
                                        targetID: action.targetID ?? item.id,
                                        value: action.value
                                    ))
                                }
                            }
                            } label: {
                                Label(action.label, systemImage: action.symbol ?? "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(HubCompactButtonStyle(primary: action.role == .primary))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .fullScreenCover(isPresented: $showsTeleprompter) {
            TeleprompterReader(text: item.detail ?? "")
        }
        .sheet(item: $noteMutation) { mutation in
            NoteMutationSheet(mutation: mutation)
                .environmentObject(client)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $calendarMutation) { mutation in
            CalendarMutationSheet(mutation: mutation)
                .environmentObject(client)
                .presentationDetents([.large])
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
        }
    }
}

private struct CalendarMutation: Identifiable {
    let targetID: String
    let draft: PersonalHubCalendarDraft
    var id: String { targetID }
}

private struct CalendarMutationSheet: View {
    let mutation: CalendarMutation
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var end: Date
    @State private var link: String
    @State private var notes: String

    init(mutation: CalendarMutation) {
        self.mutation = mutation
        _title = State(initialValue: mutation.draft.title)
        _start = State(initialValue: mutation.draft.start)
        _end = State(initialValue: mutation.draft.end)
        _link = State(initialValue: mutation.draft.joinURL?.absoluteString ?? "")
        _notes = State(initialValue: mutation.draft.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Event title", text: $title)
                DatePicker("Starts", selection: $start, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Ends", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                TextField("Meeting link", text: $link)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            .navigationTitle("Edit event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        guard let value = actionValue else { return }
                        Task {
                            await client.prepareHubAction(.init(
                                moduleID: .calendar,
                                actionID: "edit",
                                targetID: mutation.targetID,
                                value: value
                            ))
                            dismiss()
                        }
                    }
                    .disabled(actionValue == nil)
                }
            }
        }
    }

    private var actionValue: String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmedLink.isEmpty ? nil : URL(string: trimmedLink)
        guard !trimmedTitle.isEmpty, end > start, trimmedLink.isEmpty || url != nil else { return nil }
        return PersonalHubCalendarDraft(
            title: trimmedTitle,
            start: start,
            end: end,
            joinURL: url,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ).encodedActionValue()
    }
}

private struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct NoteMutation: Identifiable {
    let actionID: String
    let targetID: String
    let initialText: String
    let seed: PersonalHubNoteDraft?
    var id: String { "\(actionID):\(targetID)" }
}

private struct NoteMutationSheet: View {
    let mutation: NoteMutation
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(mutation: NoteMutation) {
        self.mutation = mutation
        _text = State(initialValue: mutation.initialText)
    }

    var body: some View {
        NavigationStack {
            Group {
                if mutation.actionID == "setCategory" {
                    Form {
                        TextField("Work, Home, Ideas…", text: $text)
                            .textInputAutocapitalization(.words)
                        Text("Leave blank to clear the category.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextEditor(text: $text)
                        .font(.body)
                        .padding(12)
                }
            }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") {
                            guard let value = actionValue else { return }
                            Task {
                                await client.prepareHubAction(.init(
                                    moduleID: .notes,
                                    actionID: mutation.actionID,
                                    targetID: mutation.targetID,
                                    value: value
                                ))
                                dismiss()
                            }
                        }
                        .disabled(actionValue == nil)
                    }
                }
        }
    }

    private var navigationTitle: String {
        switch mutation.actionID {
        case "append": return "Append to note"
        case "setCategory": return "Note category"
        default: return "Edit note"
        }
    }

    private var actionValue: String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mutation.actionID {
        case "append":
            return trimmed.isEmpty ? nil : trimmed
        case "setCategory":
            guard let seed = mutation.seed else { return nil }
            return PersonalHubNoteDraft(
                text: seed.text,
                category: trimmed.isEmpty ? nil : String(trimmed.prefix(40)),
                baseRevision: seed.baseRevision
            ).encodedActionValue()
        default:
            guard !trimmed.isEmpty else { return nil }
            return PersonalHubNoteDraft(
                text: trimmed,
                category: mutation.seed?.category,
                baseRevision: mutation.seed?.baseRevision
            ).encodedActionValue()
        }
    }
}

private struct TeleprompterReader: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @State private var fontSize: Double = 34
    @State private var wordsPerMinute = 90
    @State private var currentSegment = 0
    @State private var isPlaying = false

    private var segments: [String] {
        let words = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
        return stride(from: 0, to: words.count, by: 12).map { index in
            words[index..<min(index + 12, words.count)].joined(separator: " ")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 34) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                            Text(segment)
                                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(index < currentSegment ? .white.opacity(0.28) : .white)
                                .lineSpacing(10)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 120)
                }
                .background(Color.black.ignoresSafeArea())
                .onChange(of: currentSegment) { _, value in
                    withAnimation(.linear(duration: 0.45)) {
                        proxy.scrollTo(value, anchor: .center)
                    }
                }
                .task(id: isPlaying) {
                    guard isPlaying else { return }
                    while !Task.isCancelled, isPlaying, currentSegment < max(segments.count - 1, 0) {
                        let seconds = 720.0 / Double(max(wordsPerMinute, 1))
                        try? await Task.sleep(for: .seconds(seconds))
                        guard !Task.isCancelled, isPlaying else { return }
                        currentSegment += 1
                    }
                    if currentSegment >= max(segments.count - 1, 0) { isPlaying = false }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { fontSize = max(22, fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                    Spacer()
                    Button {
                        if currentSegment >= max(segments.count - 1, 0) { currentSegment = 0 }
                        isPlaying.toggle()
                    } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    }
                    Spacer()
                    Stepper("\(wordsPerMinute) WPM", value: $wordsPerMinute, in: 30...210, step: 15)
                        .labelsHidden()
                    Text("\(wordsPerMinute) WPM")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button { fontSize = min(64, fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                }
            }
            .toolbarBackground(.black, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
        }
    }
}

private struct CameraPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraPreviewHost()
                .ignoresSafeArea()
            Button("Done") { dismiss() }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(HubTheme.accent, in: Capsule())
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct CameraPreviewHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraPreviewController {
        CameraPreviewController()
    }

    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}
}

private final class CameraPreviewController: UIViewController {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "codeisland.camera-preview")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureSession() }
                    else { self?.showUnavailable("Camera access is off") }
                }
            }
        default:
            showUnavailable("Enable Camera access in Settings → Privacy & Security → Camera")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureSession() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else {
            showUnavailable("Front camera is unavailable")
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        sessionQueue.async { [session] in session.startRunning() }
    }

    private func showUnavailable(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

private struct PersonalHubConfirmationSheet: View {
    let prepared: PersonalHubPreparedAction
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(HubTheme.accent)
                .frame(width: 36, height: 4)

            Text("Review action")
                .font(.system(size: 21, weight: .bold))

            Text(prepared.preview)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Cancel") {
                    client.preparedAction = nil
                    dismiss()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("Do it") {
                    Task { await client.executeHubAction(prepared) }
                }
                .buttonStyle(.borderedProminent)
                .tint(HubTheme.accent)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .disabled(client.hubActionInFlight)
            }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.action.confirmation")
    }
}

private struct HubPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(HubTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HubSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HubTheme.foreground.opacity(configuration.isPressed ? 0.55 : 0.74))
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HubCompactButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color.black : HubTheme.foreground.opacity(0.7))
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(
                primary ? HubTheme.accent : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension PersonalHubMode {
    var displayTitle: String {
        switch self {
        case .auto: return "AUTO"
        case .home: return "HOME"
        case .work: return "WORK"
        case .code: return "CODE"
        }
    }
}
