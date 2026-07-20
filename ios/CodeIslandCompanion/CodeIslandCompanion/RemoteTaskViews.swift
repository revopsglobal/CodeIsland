import SwiftUI
import UniformTypeIdentifiers

extension RemoteTaskProvider {
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
}

extension RemoteTaskState {
    var displayName: String {
        switch self {
        case .waitingForMac: return "Waiting for Mac"
        case .queued: return "Queued"
        case .working: return "Working"
        case .needsYou: return "Needs You"
        case .verified: return "Verified"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var symbol: String {
        switch self {
        case .waitingForMac: return "wifi.slash"
        case .queued: return "clock"
        case .working: return "bolt.fill"
        case .needsYou: return "hand.raised.fill"
        case .verified: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .needsYou, .failed: return .orange
        case .verified: return .green
        case .working: return Color(red: 0.28, green: 0.62, blue: 1)
        case .waitingForMac, .queued, .cancelled: return Color.ciForeground.opacity(0.52)
        }
    }
}

struct RemoteTaskComposerView: View {
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: String
    @State private var selectedWorkspaceID: String?
    @State private var provider = RemoteTaskProvider.auto
    @State private var attachments: [RemoteTaskDraftAttachmentInput] = []
    @State private var claimedSharedDraftID: UUID?
    @State private var showsFileImporter = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(seedText: String? = nil, provider: RemoteTaskProvider? = nil) {
        _prompt = State(initialValue: seedText ?? "")
        _provider = State(initialValue: provider ?? .auto)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("New coding task")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text("Send a bounded edit-and-test job to your Mac.")
                            .font(.subheadline)
                            .foregroundStyle(Color.ciForeground.opacity(0.55))
                    }

                    composerCard {
                        Text("WHAT SHOULD CHANGE?")
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(Color.ciForeground.opacity(0.44))
                        TextEditor(text: $prompt)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .accessibilityLabel("Task instructions")
                            .accessibilityIdentifier("task.prompt")
                    }

                    composerCard {
                        Label("Workspace", systemImage: "folder")
                            .font(.subheadline.weight(.bold))
                        if remoteApprovals.remoteTaskWorkspaces.isEmpty {
                            Label("Open a Mac coding session or save a workspace first.", systemImage: "macbook")
                                .font(.subheadline)
                                .foregroundStyle(Color.ciForeground.opacity(0.55))
                        } else {
                            Picker("Workspace", selection: $selectedWorkspaceID) {
                                ForEach(remoteApprovals.remoteTaskWorkspaces) { workspace in
                                    Text(workspace.name).tag(Optional(workspace.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("task.workspace")
                        }
                    }

                    composerCard {
                        Label("Coding provider", systemImage: "cpu")
                            .font(.subheadline.weight(.bold))
                        Picker("Coding provider", selection: $provider) {
                            ForEach(RemoteTaskProvider.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("task.provider")
                        Text(providerDescription)
                            .font(.caption)
                            .foregroundStyle(Color.ciForeground.opacity(0.48))
                    }

                    composerCard {
                        HStack {
                            Label("Attachments", systemImage: "paperclip")
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Button("Add files") { showsFileImporter = true }
                                .font(.subheadline.weight(.semibold))
                        }
                        if attachments.isEmpty {
                            Text("Optional · 25 MB each, 50 MB total")
                                .font(.caption)
                                .foregroundStyle(Color.ciForeground.opacity(0.48))
                        } else {
                            ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc")
                                    Text(attachment.displayName)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) { attachments.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .accessibilityLabel("Remove \(attachment.displayName)")
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Edit & Test")
                                .font(.subheadline.weight(.bold))
                            Text("Workspace-safe edits and checks run automatically. Commits, publishing, external access, and destructive actions stop for your exact approval.")
                                .font(.caption)
                                .foregroundStyle(Color.ciForeground.opacity(0.52))
                        }
                    }
                    .padding(.horizontal, 4)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Button(action: submit) {
                        HStack(spacing: 10) {
                            if isSubmitting { ProgressView().tint(.black) }
                            Text(isSubmitting ? "Sending" : "Send to Mac")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.body.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.42)
                    .accessibilityIdentifier("task.submit")
                }
                .padding(20)
            }
            .background(Color.ciBackground.ignoresSafeArea())
            .foregroundStyle(Color.ciForeground)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                importFiles(result)
            }
            .task {
                importSharedDraftIfAvailable()
                if remoteApprovals.remoteTaskWorkspaces.isEmpty {
                    await remoteApprovals.refreshRemoteTasks(force: true)
                }
                selectDefaultWorkspace()
            }
            .onChange(of: remoteApprovals.remoteTaskWorkspaces) { _, _ in selectDefaultWorkspace() }
            .accessibilityIdentifier("task.composer")
        }
    }

    private var canSubmit: Bool {
        !isSubmitting
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedWorkspaceID != nil
    }

    private var providerDescription: String {
        switch provider {
        case .auto: return "Uses the best available provider for this workspace."
        case .codex: return "Routes this task to Codex on your Mac."
        case .claude: return "Routes this task to Claude Code on your Mac."
        }
    }

    @ViewBuilder
    private func composerCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.ciForeground.opacity(0.07), lineWidth: 0.5))
    }

    private func selectDefaultWorkspace() {
        guard selectedWorkspaceID == nil else { return }
        selectedWorkspaceID = remoteApprovals.remoteTaskWorkspaces.first?.id
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            attachments.append(contentsOf: urls.map { url in
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.preferredMIMEType
                    ?? "application/octet-stream"
                return RemoteTaskDraftAttachmentInput(url: url, mediaType: type)
            })
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                _ = try await remoteApprovals.enqueueRemoteTask(.init(
                    prompt: prompt,
                    workspaceID: selectedWorkspaceID,
                    provider: provider,
                    requestedProof: "Changed files, checks, warnings, and source state",
                    attachments: attachments
                ))
                if let claimedSharedDraftID, let inbox = try? SharedDraftInbox() {
                    try? inbox.acknowledge(claimedSharedDraftID)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func importSharedDraftIfAvailable() {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              attachments.isEmpty,
              let inbox = try? SharedDraftInbox(),
              let claimed = try? inbox.claimNext()
        else { return }
        prompt = claimed.manifest.text
        attachments = zip(claimed.manifest.attachments, claimed.attachmentURLs).map { attachment, url in
            RemoteTaskDraftAttachmentInput(
                url: url,
                displayName: attachment.displayName,
                mediaType: attachment.mediaType
            )
        }
        claimedSharedDraftID = claimed.manifest.id
    }
}

struct RemoteTaskSignalCard: View {
    let task: RemoteTaskSummary
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: task.state.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(task.state.tint)
                    .frame(width: 42, height: 42)
                    .background(task.state.tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(task.state.displayName.uppercased())
                            .font(.caption2.weight(.black))
                            .tracking(1)
                            .foregroundStyle(task.state.tint)
                        Spacer()
                        Text(task.provider.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ciForeground.opacity(0.42))
                    }
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(Color.ciForeground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(task.latestSummary ?? task.workspaceName)
                        .font(.subheadline)
                        .foregroundStyle(Color.ciForeground.opacity(0.54))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ciForeground.opacity(0.32))
                    .padding(.top, 4)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(task.state.tint.opacity(0.22), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.state.displayName), \(task.title)")
        .accessibilityIdentifier("task.signal.\(task.id.uuidString.lowercased())")
    }
}

struct RemoteTaskWaitingCard: View {
    let draft: RemoteTaskDraft

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.ciForeground.opacity(0.52))
                .frame(width: 42, height: 42)
                .background(Color.ciForeground.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("WAITING FOR MAC")
                    .font(.caption2.weight(.black))
                    .tracking(1)
                    .foregroundStyle(Color.ciForeground.opacity(0.48))
                Text(draft.request.prompt)
                    .font(.headline)
                    .lineLimit(2)
                Text("Saved privately on this iPhone. It will send when your Mac is reachable.")
                    .font(.caption)
                    .foregroundStyle(Color.ciForeground.opacity(0.5))
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.ciForeground.opacity(0.07), lineWidth: 0.5))
        .accessibilityIdentifier("task.waiting.\(draft.id.uuidString.lowercased())")
    }
}

struct RemoteTaskSessionsView: View {
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    let openTask: (UUID) -> Void
    let newTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coding work")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("Tasks are grouped by what needs you, not by polling order.")
                        .font(.caption)
                        .foregroundStyle(Color.ciForeground.opacity(0.5))
                }
                Spacer()
                Button(action: newTask) {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(Color.orange, in: Circle())
                        .foregroundStyle(.black)
                }
                .accessibilityLabel("New coding task")
            }

            ForEach(groups, id: \.title) { group in
                if !group.tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title.uppercased())
                            .font(.caption2.weight(.black))
                            .tracking(1.1)
                            .foregroundStyle(Color.ciForeground.opacity(0.42))
                        ForEach(group.tasks) { task in
                            taskRow(task)
                        }
                    }
                }
            }

            if !remoteApprovals.remoteTaskDrafts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WAITING FOR MAC")
                        .font(.caption2.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(Color.ciForeground.opacity(0.42))
                    ForEach(remoteApprovals.remoteTaskDrafts) { draft in
                        RemoteTaskWaitingCard(draft: draft)
                    }
                }
            }

            if remoteApprovals.remoteTasks.isEmpty && remoteApprovals.remoteTaskDrafts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28, weight: .semibold))
                    Text("No coding tasks yet")
                        .font(.headline)
                    Button("Send your first task", action: newTask)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .foregroundStyle(Color.ciForeground.opacity(0.62))
                .frame(maxWidth: .infinity, minHeight: 180)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .foregroundStyle(Color.ciForeground)
        .accessibilityIdentifier("task.sessions")
    }

    private var groups: [(title: String, tasks: [RemoteTaskSummary])] {
        let tasks = remoteApprovals.remoteTasks.sorted { $0.updatedAt > $1.updatedAt }
        return [
            ("Needs You", tasks.filter { $0.state == .needsYou || $0.state == .failed }),
            ("Active", tasks.filter { $0.state == .working || $0.state == .queued || $0.state == .waitingForMac }),
            ("Completed", tasks.filter { $0.state == .verified || $0.state == .cancelled }),
        ]
    }

    private func taskRow(_ task: RemoteTaskSummary) -> some View {
        Button { openTask(task.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: task.state.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(task.state.tint)
                    .frame(width: 34, height: 34)
                    .background(task.state.tint.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.ciForeground)
                        .lineLimit(2)
                    Text("\(task.workspaceName) · \(task.provider.displayName) · \(task.state.displayName)")
                        .font(.caption)
                        .foregroundStyle(Color.ciForeground.opacity(0.48))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ciForeground.opacity(0.28))
            }
            .padding(13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.ciForeground.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task.row.\(task.id.uuidString.lowercased())")
    }
}

struct RemoteTaskDetailView: View {
    let taskID: UUID
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @EnvironmentObject private var liveActivity: LiveActivityController
    @Environment(\.dismiss) private var dismiss
    @State private var followUp = ""
    @State private var isSending = false
    @State private var showsCancelConfirmation = false

    private var task: RemoteTaskSummary? {
        remoteApprovals.remoteTasks.first(where: { $0.id == taskID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let task {
                    VStack(alignment: .leading, spacing: 18) {
                        detailHeader(task)

                        if let latestSummary = task.latestSummary {
                            detailCard(title: "Latest", symbol: "waveform.path") {
                                Text(latestSummary)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }

                        detailCard(title: "Scope", symbol: "checkmark.shield") {
                            Label("Edit & Test", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(task.workspaceName) · \(task.provider.displayName)")
                                .foregroundStyle(Color.ciForeground.opacity(0.56))
                        }

                        if !task.state.isTerminal {
                            Button {
                                if liveActivity.isFollowing(taskID: task.id) {
                                    liveActivity.unfollowTask()
                                } else {
                                    liveActivity.follow(task)
                                }
                            } label: {
                                Label(
                                    liveActivity.isFollowing(taskID: task.id) ? "Stop following" : "Follow in Dynamic Island",
                                    systemImage: liveActivity.isFollowing(taskID: task.id) ? "waveform.slash" : "waveform"
                                )
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                            .accessibilityLabel(
                                liveActivity.isFollowing(taskID: task.id)
                                    ? "Stop following in Dynamic Island"
                                    : "Follow in Dynamic Island"
                            )
                            .accessibilityIdentifier("task.follow")
                        }

                        if let evidence = task.evidence {
                            evidenceCard(evidence)
                        }

                        if !task.state.isTerminal {
                            detailCard(title: "Continue", symbol: "arrow.turn.down.right") {
                                TextField("Add detail or answer the agent", text: $followUp, axis: .vertical)
                                    .lineLimit(2...6)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color.ciForeground.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Button(action: sendFollowUp) {
                                    Text(isSending ? "Sending" : "Send follow-up")
                                        .font(.subheadline.weight(.bold))
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)

                                Button("Cancel task", role: .destructive) { showsCancelConfirmation = true }
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                        } else if task.state == .failed {
                            detailCard(title: "Clear attention", symbol: "archivebox") {
                                Text("Keep this failure in task history, but remove it from Needs You.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.ciForeground.opacity(0.56))
                                Button("Dismiss failure") { showsCancelConfirmation = true }
                                    .font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .buttonStyle(.bordered)
                                    .tint(.orange)
                                    .accessibilityIdentifier("task.dismiss-failure")
                            }
                        }
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView("Task unavailable", systemImage: "questionmark.folder", description: Text("Refresh the Mac connection and try again."))
                        .padding(.top, 80)
                }
            }
            .background(Color.ciBackground.ignoresSafeArea())
            .foregroundStyle(Color.ciForeground)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog(
                task?.state == .failed ? "Dismiss this failure?" : "Cancel this task?",
                isPresented: $showsCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button(task?.state == .failed ? "Dismiss failure" : "Cancel task", role: .destructive) {
                    Task {
                        await remoteApprovals.cancelRemoteTask(taskID: taskID)
                        dismiss()
                    }
                }
                Button(task?.state == .failed ? "Keep in Needs You" : "Keep working", role: .cancel) {}
            }
            .accessibilityIdentifier("task.detail.\(taskID.uuidString.lowercased())")
        }
    }

    private func detailHeader(_ task: RemoteTaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(task.state.displayName, systemImage: task.state.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(task.state.tint)
                Spacer()
                Text(task.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(Color.ciForeground.opacity(0.42))
            }
            Text(task.title)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .textSelection(.enabled)
            Text(task.state == .verified ? "Verified by checks reported from your Mac." : "Live status from your paired Mac.")
                .font(.caption)
                .foregroundStyle(Color.ciForeground.opacity(0.5))
        }
    }

    @ViewBuilder
    private func detailCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.ciForeground.opacity(0.07), lineWidth: 0.5))
    }

    private func evidenceCard(_ evidence: RemoteTaskEvidence) -> some View {
        detailCard(title: "Completion evidence", symbol: "checklist.checked") {
            if let branch = evidence.branch {
                evidenceRow("Branch", value: branch, symbol: "arrow.triangle.branch")
            }
            evidenceRow("Source", value: evidence.sourceState.rawValue.capitalized, symbol: "shippingbox")
            if !evidence.changedFiles.isEmpty {
                Divider()
                Text("Changed files")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ciForeground.opacity(0.45))
                ForEach(evidence.changedFiles) { file in
                    evidenceRow(file.kind.rawValue.capitalized, value: file.path, symbol: "doc")
                }
            }
            if !evidence.checks.isEmpty {
                Divider()
                Text("Checks")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.ciForeground.opacity(0.45))
                ForEach(Array(evidence.checks.enumerated()), id: \.offset) { _, check in
                    evidenceRow(check.exitCode == 0 ? "Passed" : "Failed", value: check.summary, symbol: check.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                }
            }
            ForEach(evidence.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func evidenceRow(_ label: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption.weight(.bold))
                Text(value).font(.caption).foregroundStyle(Color.ciForeground.opacity(0.55)).textSelection(.enabled)
            }
        }
    }

    private func sendFollowUp() {
        let text = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        Task {
            await remoteApprovals.followUpRemoteTask(taskID: taskID, text: text)
            followUp = ""
            isSending = false
        }
    }
}
