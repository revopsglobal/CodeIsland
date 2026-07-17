import SwiftUI
import UIKit
import AVFoundation

private enum HubTheme {
    static let accent = Color(red: 1.0, green: 0.69, blue: 0.0)
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
                        .foregroundStyle(.ciForeground.opacity(0.48))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(snapshot.generatedAt, style: .time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.ciForeground.opacity(0.34))
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

            if let message = client.hubActionMessage {
                Text(message)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.ciForeground.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("hub.action.message")
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
                            client.selectedMode == mode ? Color.black : Color.ciForeground.opacity(0.58)
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
                .foregroundStyle(.ciForeground.opacity(0.86))
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.ciForeground.opacity(0.48))
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
    @State private var eventStart = Date().addingTimeInterval(3_600)
    @State private var eventEnd = Date().addingTimeInterval(7_200)
    @State private var meetingLink = ""
    @State private var reminderHasDue = false
    @State private var reminderDue = Date().addingTimeInterval(3_600)
    @State private var showsCameraPreview = false

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
                        .foregroundStyle(.ciForeground.opacity(0.9))
                    Text(module.summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.ciForeground.opacity(0.5))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)
                availabilityMark
            }

            if let detail = module.detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.ciForeground.opacity(0.38))
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
                                || (module.id == .teleprompter && action.id == "set")
                                || (module.id == .claude && action.id == "ask") {
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
        .accessibilityIdentifier("hub.module.\(module.id.rawValue)")
        .fullScreenCover(isPresented: $showsCameraPreview) {
            CameraPreviewScreen()
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
                .foregroundStyle(.ciForeground.opacity(0.3))
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
                targetID: action.targetID
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
            VStack(alignment: .leading, spacing: 8) {
                hubTextField("New task", text: $composerText)
                Toggle("Set due date", isOn: $reminderHasDue)
                    .font(.system(size: 11, weight: .semibold))
                if reminderHasDue {
                    DatePicker("Due", selection: $reminderDue, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .font(.system(size: 11, weight: .semibold))
                }
                reviewButton(value: PersonalHubReminderDraft(
                    title: composerText.trimmingCharacters(in: .whitespacesAndNewlines),
                    due: reminderHasDue ? reminderDue : nil
                ).encodedActionValue())
            }
        } else if module.id == .teleprompter {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $composerText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.ciForeground)
                    .frame(minHeight: 110)
                    .padding(7)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                reviewButton(
                    actionID: "set",
                    value: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        } else if module.id == .claude {
            HStack(spacing: 7) {
                hubTextField("Ask Claude", text: $composerText)
                reviewButton(
                    actionID: "ask",
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
            .foregroundStyle(.ciForeground)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("hub.\(module.id.rawValue).composer")
    }

    private func reviewButton(actionID: String = "add", value: String?) -> some View {
        Button("Review") {
            guard let value, !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task {
                await client.prepareHubAction(.init(
                    moduleID: module.id,
                    actionID: actionID,
                    value: value
                ))
            }
        }
        .buttonStyle(HubPrimaryButtonStyle())
        .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value == nil)
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
}

private struct PersonalHubItemRow: View {
    let moduleID: PersonalHubModuleID
    let item: PersonalHubItem
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.openURL) private var openURL
    @State private var showsTeleprompter = false
    @State private var noteMutation: NoteMutation?
    @State private var sharedFile: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.ciForeground.opacity(0.42))
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.ciForeground.opacity(0.84))
                        .lineLimit(2)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.ciForeground.opacity(0.42))
                    }
                }
                Spacer(minLength: 4)
            }

            if let progress = item.progress {
                ProgressView(value: progress).tint(HubTheme.accent)
            }

            if !item.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.actions) { action in
                        Button {
                            if action.id == "downloadToDevice" {
                                Task {
                                    if let url = await client.downloadShelfFile(id: item.id, filename: item.title) {
                                        sharedFile = SharedFile(url: url)
                                    }
                                }
                            } else if moduleID == .notes, ["append", "replace"].contains(action.id) {
                                noteMutation = .init(
                                    actionID: action.id,
                                    targetID: action.targetID ?? item.id,
                                    initialText: action.id == "replace" ? (item.detail ?? "") : ""
                                )
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
                                        targetID: action.targetID ?? item.id
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
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
        }
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
            TextEditor(text: $text)
                .font(.body)
                .padding(12)
                .navigationTitle(mutation.actionID == "append" ? "Append to note" : "Edit note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Review") {
                            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.isEmpty else { return }
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
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
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
            .foregroundStyle(.ciForeground.opacity(configuration.isPressed ? 0.55 : 0.74))
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HubCompactButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color.black : Color.ciForeground.opacity(0.7))
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
