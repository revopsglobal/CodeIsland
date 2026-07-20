import AppKit
import CodeIslandCore
import SwiftUI

enum RemoteTaskMacSection: String, CaseIterable, Identifiable {
    case needsYou
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsYou: return "Needs You"
        case .active: return "Active"
        case .completed: return "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .needsYou: return "exclamationmark.bubble.fill"
        case .active: return "waveform.path.ecg"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

struct RemoteTaskMacPortfolio: Equatable {
    let needsYou: [RemoteTaskSummary]
    let active: [RemoteTaskSummary]
    let completed: [RemoteTaskSummary]

    subscript(section: RemoteTaskMacSection) -> [RemoteTaskSummary] {
        switch section {
        case .needsYou: return needsYou
        case .active: return active
        case .completed: return completed
        }
    }

    static func build(from tasks: [RemoteTaskSummary]) -> Self {
        let newestFirst: ([RemoteTaskSummary]) -> [RemoteTaskSummary] = {
            $0.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
        return Self(
            needsYou: newestFirst(tasks.filter { $0.state == .needsYou || $0.state == .failed }),
            active: newestFirst(tasks.filter {
                $0.state == .waitingForMac || $0.state == .queued || $0.state == .working
            }),
            completed: newestFirst(tasks.filter { $0.state == .verified || $0.state == .cancelled })
        )
    }
}

struct RemoteTaskSessionCandidate: Equatable {
    let id: String
    let provider: String
    let workspacePath: String?
    let updatedAt: Date
}

enum RemoteTaskOpenTargetResolver {
    static func resolve(
        providerSessionID: String?,
        provider: RemoteTaskProvider,
        workspacePath: String?,
        candidates: [RemoteTaskSessionCandidate]
    ) -> String? {
        let expectedProvider = provider.rawValue
        func matchesProvider(_ value: String) -> Bool {
            let normalized = value.lowercased()
            return normalized == expectedProvider
                || (expectedProvider == "claude" && normalized.hasPrefix("claude"))
                || (expectedProvider == "codex" && normalized.hasPrefix("codex"))
        }

        if let providerSessionID,
           let exact = candidates.first(where: {
               $0.id == providerSessionID && matchesProvider($0.provider)
           }) {
            return exact.id
        }

        guard let workspacePath else { return nil }
        return candidates
            .filter { matchesProvider($0.provider) && $0.workspacePath == workspacePath }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
            .first?.id
    }
}

@MainActor
final class RemoteTasksWindowController: NSWindowController, NSWindowDelegate {
    static let shared = RemoteTasksWindowController()

    private var retainedAppState: AppState?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(appState: AppState) {
        retainedAppState = appState
        if window == nil {
            let content = RemoteTasksMacView(appState: appState)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = "Code Island Tasks"
            window.setContentSize(NSSize(width: 980, height: 700))
            window.minSize = NSSize(width: 760, height: 540)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct RemoteTasksMacView: View {
    let appState: AppState

    @ObservedObject private var service = RemoteApprovalService.shared
    @State private var selection: RemoteTaskMacSection = .needsYou
    @State private var selectedTaskID: UUID?
    @State private var showingComposer = false
    @State private var actionMessage: String?

    private let accent = Color(red: 1.0, green: 0.62, blue: 0.0)

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } content: {
            taskList
                .navigationSplitViewColumnWidth(min: 330, ideal: 390, max: 480)
        } detail: {
            detail
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingComposer = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .foregroundStyle(.black)
                .disabled(service.remoteTaskWorkspaces.isEmpty)
            }
        }
        .sheet(isPresented: $showingComposer) {
            RemoteTaskMacComposer { prompt, workspace, provider in
                do {
                    let task = try service.createLocalRemoteTask(
                        prompt: prompt,
                        workspaceID: workspace,
                        provider: provider
                    )
                    selectedTaskID = task.id
                    selection = task.state == .needsYou ? .needsYou : .active
                    showingComposer = false
                } catch {
                    actionMessage = error.localizedDescription
                }
            }
            .environmentObject(service)
        }
        .onAppear {
            service.refreshRemoteTaskPublishedState()
            repairSelection()
        }
        .onChange(of: service.remoteTasks) { _, _ in repairSelection() }
    }

    private var portfolio: RemoteTaskMacPortfolio {
        .build(from: service.remoteTasks)
    }

    private var selectedTask: RemoteTaskSummary? {
        guard let selectedTaskID else { return nil }
        return service.remoteTasks.first(where: { $0.id == selectedTaskID })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent.gradient)
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CODE ISLAND")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Text(service.running ? "Private Mac online" : "Mac service offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                ForEach(RemoteTaskMacSection.allCases) { section in
                    Button {
                        selection = section
                        selectedTaskID = portfolio[section].first?.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .frame(width: 18)
                            Text(section.title)
                            Spacer()
                            Text("\(portfolio[section].count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(selection == section ? .primary : .secondary)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 38)
                        .background(
                            selection == section ? Color.primary.opacity(0.09) : .clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                Label("Edit and test only", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                Text("Commits, pushes, merges, deploys, and releases always stop for review.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(.ultraThinMaterial)
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selection.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(sectionSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Divider()

            if portfolio[selection].isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: selection == .needsYou ? "checkmark.circle" : selection.symbol,
                    description: Text(emptyDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(portfolio[selection]) { task in
                            RemoteTaskMacRow(task: task, selected: selectedTaskID == task.id)
                                .onTapGesture { selectedTaskID = task.id }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let task = selectedTask {
            RemoteTaskMacDetail(
                task: task,
                message: actionMessage,
                open: {
                    actionMessage = service.openRemoteTaskOnMac(id: task.id)
                        ? "Opened the exact coding session"
                        : "No exact live session was found; opened the workspace instead"
                },
                followUp: { text in
                    do {
                        try service.followUpLocalRemoteTask(id: task.id, text: text)
                        actionMessage = "Follow-up sent to this exact task"
                    } catch { actionMessage = error.localizedDescription }
                },
                cancel: {
                    do {
                        try service.cancelLocalRemoteTask(id: task.id)
                        actionMessage = "Task cancelled"
                    } catch { actionMessage = error.localizedDescription }
                }
            )
        } else {
            ContentUnavailableView(
                "Select a task",
                systemImage: "terminal",
                description: Text("Provider, workspace, receipts, evidence, and handoff controls stay attached to one exact task.")
            )
        }
    }

    private var sectionSubtitle: String {
        switch selection {
        case .needsYou: return "Only decisions, failures, and blocked work."
        case .active: return "Working, queued, and waiting for this Mac."
        case .completed: return "Verified work and intentionally cancelled tasks."
        }
    }

    private var emptyTitle: String {
        selection == .needsYou ? "Nothing needs you" : "No \(selection.title.lowercased()) tasks"
    }

    private var emptyDescription: String {
        selection == .needsYou
            ? "Routine progress stays quiet until a real decision is required."
            : "Create a coding task from this Mac, Buddy, Shortcuts, or the iPhone share sheet."
    }

    private func repairSelection() {
        if let selectedTaskID, service.remoteTasks.contains(where: { $0.id == selectedTaskID }) { return }
        if !portfolio.needsYou.isEmpty {
            selection = .needsYou
            selectedTaskID = portfolio.needsYou.first?.id
        } else if !portfolio.active.isEmpty {
            selection = .active
            selectedTaskID = portfolio.active.first?.id
        } else {
            selection = .completed
            selectedTaskID = portfolio.completed.first?.id
        }
    }
}

private struct RemoteTaskMacRow: View {
    let task: RemoteTaskSummary
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RemoteTaskMacStateBadge(state: task.state)
                Spacer(minLength: 8)
                Text(task.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(task.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 6) {
                Label(task.workspaceName, systemImage: "folder")
                Text("·")
                Text(task.provider.rawValue.capitalized)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(13)
        .background(
            selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(selected ? Color.accentColor.opacity(0.42) : Color.primary.opacity(0.06))
        }
        .contentShape(Rectangle())
    }
}

private struct RemoteTaskMacDetail: View {
    let task: RemoteTaskSummary
    let message: String?
    let open: () -> Void
    let followUp: (String) -> Void
    let cancel: () -> Void

    @State private var followUpText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    RemoteTaskMacStateBadge(state: task.state)
                    Text(task.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .textSelection(.enabled)
                    Text(task.latestSummary ?? "Accepted by this Mac")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    detailChip(task.provider.rawValue.capitalized, symbol: "cpu")
                    detailChip(task.workspaceName, symbol: "folder.fill")
                    detailChip("Edit & test", symbol: "lock.shield.fill")
                }

                Button(action: open) {
                    Label("Open exact session", systemImage: "arrow.up.forward.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let evidence = task.evidence {
                    evidenceSection(evidence)
                }

                if !task.state.isTerminal {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("FOLLOW UP")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("Add detail or answer the agent", text: $followUpText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)
                        HStack {
                            Button("Cancel task", role: .destructive, action: cancel)
                            Spacer()
                            Button("Send follow-up") {
                                let text = followUpText
                                followUpText = ""
                                followUp(text)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let message {
                    Text(message)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(26)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func detailChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private func evidenceSection(_ evidence: RemoteTaskEvidence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VERIFIED EVIDENCE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if let branch = evidence.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .textSelection(.enabled)
            }
            ForEach(evidence.checks.indices, id: \.self) { index in
                let check = evidence.checks[index]
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: check.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.exitCode == 0 ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.command).font(.system(.caption, design: .monospaced))
                        Text(check.summary).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if evidence.checks.isEmpty {
                Text("No executable check receipt yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RemoteTaskMacStateBadge: View {
    let state: RemoteTaskState

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var label: String {
        switch state {
        case .waitingForMac: return "Waiting for Mac"
        case .queued: return "Queued"
        case .working: return "Working"
        case .needsYou: return "Needs You"
        case .verified: return "Verified"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var symbol: String {
        switch state {
        case .waitingForMac: return "wifi.slash"
        case .queued: return "clock"
        case .working: return "waveform.path.ecg"
        case .needsYou: return "exclamationmark.bubble.fill"
        case .verified: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .needsYou: return .orange
        case .failed: return .red
        case .verified: return .green
        case .working: return .blue
        case .waitingForMac, .queued, .cancelled: return .secondary
        }
    }
}

private struct RemoteTaskMacComposer: View {
    let submit: (String, String, RemoteTaskProvider) -> Void

    @EnvironmentObject private var service: RemoteApprovalService
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var workspaceID = ""
    @State private var provider: RemoteTaskProvider = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New coding task")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Review the boundary before anything runs.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            TextField("What should Codex or Claude edit and test?", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...10)

            Picker("Workspace", selection: $workspaceID) {
                ForEach(service.remoteTaskWorkspaces) { workspace in
                    Text(workspace.name).tag(workspace.id)
                }
            }
            Picker("Provider", selection: $provider) {
                Text("Automatic").tag(RemoteTaskProvider.auto)
                Text("Codex").tag(RemoteTaskProvider.codex)
                Text("Claude").tag(RemoteTaskProvider.claude)
            }
            .pickerStyle(.segmented)

            Label(
                "Reads, edits, formats, and tests may continue. Commit, push, merge, deploy, publish, and release require your approval.",
                systemImage: "lock.shield.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Start task") { submit(prompt, workspaceID, provider) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || workspaceID.isEmpty
                    )
            }
        }
        .padding(26)
        .frame(width: 560)
        .onAppear { workspaceID = service.remoteTaskWorkspaces.first?.id ?? "" }
    }
}
