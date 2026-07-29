import SwiftUI

private enum AgentOpsPrimaryDestination: String, CaseIterable, Identifiable {
    case voice
    case work
    case attention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice: return "Voice"
        case .work: return "Work"
        case .attention: return "Attention"
        }
    }

    var symbol: String {
        switch self {
        case .voice: return "waveform"
        case .work: return "checklist"
        case .attention: return "exclamationmark.bubble"
        }
    }
}

private enum AgentOpsShellSheet: String, Identifiable {
    case buddy

    var id: String { rawValue }
}

struct CompanionCommandCenterView: View {
    let topPadding: CGFloat

    @EnvironmentObject private var agentOps: AgentOpsRootStore
    @StateObject private var voiceModel: AgentOpsVoiceViewModel
    @State private var destination: AgentOpsPrimaryDestination
    @State private var presentedSheet: AgentOpsShellSheet?

    private let usesAgentOpsShell: Bool

    init(topPadding: CGFloat) {
        self.topPadding = topPadding
        let arguments = ProcessInfo.processInfo.arguments
        // AgentOps decommission (2026-07-28): the companion UI is the default
        // surface again. The voice shell is opt-in only, via the explicit
        // -AgentOpsShellEnabled launch argument or the UI-test voice mocks,
        // until the full AgentOps removal lands.
        usesAgentOpsShell = arguments.contains("-AgentOpsShellEnabled")
            || arguments.contains("-AgentOpsVoiceMock")
        let scenario = AgentOpsVoiceMockScenario.from(arguments: arguments)
        _voiceModel = StateObject(
            wrappedValue: AgentOpsVoiceViewModel(mockScenario: scenario)
        )
        if let index = arguments.firstIndex(of: "-AgentOpsMockDestination"),
           arguments.indices.contains(index + 1),
           let requested = AgentOpsPrimaryDestination(
               rawValue: arguments[index + 1].lowercased()
           ) {
            _destination = State(initialValue: requested)
        } else {
            _destination = State(initialValue: .voice)
        }
    }

    var body: some View {
        if usesAgentOpsShell {
            agentOpsShell
        } else {
            LegacyCompanionCommandCenterView(topPadding: topPadding)
        }
    }

    private var agentOpsShell: some View {
        ZStack {
            Color.ciBackground.ignoresSafeArea()

            Group {
                switch destination {
                case .voice:
                    AgentOpsVoiceView(model: voiceModel, topPadding: topPadding)
                case .work:
                    AgentOpsWorkView()
                case .attention:
                    AgentOpsAttentionView()
                }
            }
            .frame(maxWidth: 720, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AgentOpsDestinationDock(
                destination: $destination,
                attentionCount: agentOps.approvals.filter {
                    $0.status == .pending
                }.count,
                openBuddy: { presentedSheet = .buddy }
            )
        }
        .sheet(item: $presentedSheet) { _ in
            LegacyCompanionCommandCenterView(topPadding: 22)
                .accessibilityIdentifier("agentops.buddy.sheet")
        }
        .onAppear { applyAgentOpsNavigation(agentOps.navigationTarget) }
        .onChange(of: agentOps.navigationTarget) { _, target in
            applyAgentOpsNavigation(target)
        }
    }

    private func applyAgentOpsNavigation(
        _ target: AgentOpsNavigationTarget?
    ) {
        switch target {
        case .approval:
            destination = .attention
        case .task:
            destination = .work
        case nil:
            break
        }
    }
}

private struct AgentOpsDestinationDock: View {
    @Binding var destination: AgentOpsPrimaryDestination
    let attentionCount: Int
    let openBuddy: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AgentOpsPrimaryDestination.allCases) { item in
                Button {
                    destination = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .overlay(alignment: .topTrailing) {
                                if item == .attention, attentionCount > 0 {
                                    Circle()
                                        .fill(.orange)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 5, y: -3)
                                }
                            }
                        Text(item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    destination == item
                        ? Color.accentColor
                        : Color.ciForeground.opacity(0.62)
                )
                .accessibilityIdentifier(
                    "agentops.destination.\(item.rawValue)"
                )
                .accessibilityAddTraits(
                    destination == item ? .isSelected : []
                )
            }

            Button(action: openBuddy) {
                VStack(spacing: 3) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Buddy")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ciForeground.opacity(0.62))
            .accessibilityIdentifier("agentops.openBuddy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .dynamicTypeSize(.xSmall ... .accessibility3)
    }
}

private enum CommandCenterDestination: String, CaseIterable, Identifiable {
    case now
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "Now"
        case .sessions: return "Sessions"
        }
    }

    var symbol: String {
        switch self {
        case .now: return "sparkles"
        case .sessions: return "terminal"
        }
    }
}

private enum CommandCenterSheet: Identifiable {
    case more
    case composer(String?, RemoteTaskProvider?)
    case task(UUID)

    var id: String {
        switch self {
        case .more: return "more"
        case .composer: return "composer"
        case .task(let id): return "task:\(id.uuidString.lowercased())"
        }
    }
}

struct LegacyCompanionCommandCenterView: View {
    let topPadding: CGFloat

    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var destination = CommandCenterDestination.now
    @State private var presentedSheet: CommandCenterSheet?
    @State private var showsCaptureChoices = false
    @State private var selectedAttentionID: String?
    @State private var followedTaskID: UUID?
    @AppStorage("companion.reviewedVerifiedTaskIDs")
    private var reviewedVerifiedTaskIDsPayload = "[]"

    var body: some View {
        ZStack {
            CompanionCommandBackground()

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    CompanionPresenceHeader()
                        .environmentObject(connection)
                        .environmentObject(remoteApprovals)

                    if destination != .now || attentionCount == 0 {
                        CompanionSignalBoard(
                            approvalCount: remoteApprovals.approvals.count,
                            questionCount: remoteApprovals.questions.count,
                            urgentTaskCount: urgentTaskCount,
                            activeTaskCount: activeTaskCount,
                            connectionState: remoteApprovals.state,
                            activeSessionStatus: connection.latestState?.status
                        )
                    }

                    switch destination {
                    case .now:
                        nowContent
                    case .sessions:
                        CompanionSessionsSurface(
                            openTask: { presentedSheet = .task($0) },
                            newTask: { presentedSheet = .composer(nil, nil) }
                        )
                            .environmentObject(connection)
                            .environmentObject(liveActivity)
                            .environmentObject(remoteApprovals)
                            .transition(.opacity)
                    }

                    if let error = liveActivity.lastError {
                        Label(error, systemImage: "livephoto.slash")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("companion.liveActivity.error")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CompanionActionDock(
                destination: destination,
                attentionCount: attentionCount,
                select: select,
                capture: { showsCaptureChoices = true },
                more: { presentedSheet = .more }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .dynamicTypeSize(.xSmall ... .xxxLarge)
        }
        .confirmationDialog("Capture", isPresented: $showsCaptureChoices) {
            Button("New coding task") { presentedSheet = .composer(nil, nil) }
            Button("New reminder") { openQuickJot(.task) }
            Button("New note") { openQuickJot(.note) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Send coding work to your Mac or capture a personal item.")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .more:
                PersonalHubDirectorySurface(dismiss: { presentedSheet = nil })
                    .environmentObject(remoteApprovals)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("companion.more.sheet")
            case .composer(let seedText, let provider):
                RemoteTaskComposerView(seedText: seedText, provider: provider)
                    .environmentObject(remoteApprovals)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .task(let id):
                RemoteTaskDetailView(taskID: id)
                    .environmentObject(remoteApprovals)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: remoteApprovals.highlightedHubModuleID) { _, moduleID in
            guard moduleID != nil else { return }
            presentedSheet = .more
        }
        .onChange(of: attentionCount) { oldValue, newValue in
            guard newValue > oldValue else { return }
            select(.now)
        }
        .onChange(of: attentionCandidates) { _, candidates in
            selectedAttentionID = RemoteTaskPresentationModel.selection(
                previousID: selectedAttentionID,
                candidates: candidates
            )
            if followedTaskID == nil,
               let latest = remoteApprovals.remoteTasks
                .filter({ !$0.state.isTerminal })
                .max(by: { $0.updatedAt < $1.updatedAt }) {
                followedTaskID = latest.id
            }
        }
        .onChange(of: remoteApprovals.remoteTaskDeepLinkDestination) { _, route in
            guard let route else { return }
            present(route)
        }
        .onAppear {
            if remoteApprovals.highlightedHubModuleID != nil {
                presentedSheet = .more
            }
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-CodeIslandCompanionMockDestination"),
               arguments.indices.contains(index + 1),
               arguments[index + 1].lowercased() == "sessions" {
                destination = .sessions
            }
            if arguments.contains("-CodeIslandCompanionMockMore") {
                presentedSheet = .more
            }
#endif
            selectedAttentionID = RemoteTaskPresentationModel.selection(
                previousID: selectedAttentionID,
                candidates: attentionCandidates
            )
            if let route = remoteApprovals.remoteTaskDeepLinkDestination {
                present(route)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.commandCenter")
    }

    @ViewBuilder
    private var nowContent: some View {
        RemoteApprovalSurface()
            .environmentObject(remoteApprovals)

        if let task = selectedTask {
            RemoteTaskSignalCard(task: task) {
                if task.state == .verified { markVerifiedTaskReviewed(task.id) }
                presentedSheet = .task(task.id)
            }
        } else if let draft = selectedDraft {
            RemoteTaskWaitingCard(draft: draft)
        }

        if CompanionFirst.isEnabled, remoteApprovals.hasPairingCredential, attentionCandidates.isEmpty {
            // Pair 2: the positive half of companion-first. When nothing needs
            // you, lead with what the agents actually did while you were away.
            CompanionAwayLedger(tasks: remoteApprovals.remoteTasks)
        }

        if remoteApprovals.hasPairingCredential, attentionCandidates.isEmpty {
            CompanionTodayTimeline(
                snapshot: remoteApprovals.hubSnapshot,
                openSessions: { select(.sessions) },
                openMore: { presentedSheet = .more }
            )
        }
    }

    private var attentionCount: Int {
        RemoteTaskPresentationModel.immediateAttentionCount(in: attentionCandidates)
    }

    private var reviewedVerifiedTaskIDs: Set<UUID> {
        RemoteTaskReviewPersistence.decode(reviewedVerifiedTaskIDsPayload)
    }

    private func markVerifiedTaskReviewed(_ id: UUID) {
        var reviewed = reviewedVerifiedTaskIDs
        reviewed.insert(id)
        reviewedVerifiedTaskIDsPayload = RemoteTaskReviewPersistence.encode(reviewed)
    }

    private var urgentTaskCount: Int {
        remoteApprovals.remoteTasks.filter { $0.state == .needsYou || $0.state == .failed }.count
    }

    private var activeTaskCount: Int {
        remoteApprovals.remoteTasks.filter { !$0.state.isTerminal }.count
            + remoteApprovals.remoteTaskDrafts.count
    }

    private var attentionCandidates: [RemoteTaskAttentionCandidate] {
        RemoteTaskPresentationModel.candidates(
            approvalIDs: remoteApprovals.approvals.map(\.id),
            questionIDs: remoteApprovals.questions.map(\.id),
            tasks: remoteApprovals.remoteTasks,
            drafts: remoteApprovals.remoteTaskDrafts,
            followedTaskID: followedTaskID,
            reviewedVerifiedTaskIDs: reviewedVerifiedTaskIDs
        )
    }

    private var selectedTask: RemoteTaskSummary? {
        guard let selectedAttentionID,
              let candidate = attentionCandidates.first(where: { $0.id == selectedAttentionID }),
              let taskID = candidate.taskID,
              candidate.kind != .approval,
              candidate.kind != .question
        else { return nil }
        return remoteApprovals.remoteTasks.first(where: { $0.id == taskID })
    }

    private var selectedDraft: RemoteTaskDraft? {
        guard let selectedAttentionID, selectedAttentionID.hasPrefix("draft:") else { return nil }
        return remoteApprovals.remoteTaskDrafts.first {
            "draft:\($0.id.uuidString.lowercased())" == selectedAttentionID
        }
    }

    private func select(_ newDestination: CommandCenterDestination) {
        if reduceMotion {
            destination = newDestination
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                destination = newDestination
            }
        }
    }

    private func openQuickJot(_ destination: BuddyQuickJotDestination) {
        remoteApprovals.quickJotDestination = destination
        presentedSheet = .more
    }

    private func present(_ route: RemoteTaskDeepLinkDestination) {
        switch route {
        case .detail(let id): presentedSheet = .task(id)
        case .composer(let text, let provider): presentedSheet = .composer(text, provider)
        case .needsYou:
            select(.now)
        case .sessions:
            select(.sessions)
        }
        remoteApprovals.consumeRemoteTaskDeepLinkDestination()
    }
}

private struct CompanionSignalBoard: View {
    let approvalCount: Int
    let questionCount: Int
    let urgentTaskCount: Int
    let activeTaskCount: Int
    let connectionState: RemoteApprovalClient.ConnectionState
    let activeSessionStatus: CompanionStatus?

    private var remoteNeedsAttention: Bool {
        approvalCount + questionCount + urgentTaskCount > 0
    }

    private var sessionNeedsAttention: Bool {
        guard let activeSessionStatus else { return false }
        switch activeSessionStatus {
        case .waitingApproval, .waitingQuestion: return true
        case .running, .processing, .idle: return false
        }
    }

    private var needsAttention: Bool {
        remoteNeedsAttention || sessionNeedsAttention
    }

    private var attentionSubtitle: String {
        if remoteNeedsAttention {
            return "Review what needs Greg before anything else."
        }
        if sessionNeedsAttention {
            return "A nearby session is waiting for you. Answer it from Sessions in the dock."
        }
        if activeTaskCount > 0 {
            return "Your Mac is working. Routine updates stay in place."
        }
        return "No approvals, questions, or coding tasks are waiting."
    }

    private var connectionTitle: String {
        switch connectionState {
        case .connected: return "Mac online"
        case .connecting: return "Connecting"
        case .offline: return "Mac offline"
        case .unpaired: return "Pair Mac"
        }
    }

    private var connectionSymbol: String {
        switch connectionState {
        case .connected: return "checkmark"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        case .unpaired: return "link.badge.plus"
        }
    }

    private var sessionTitle: String {
        guard let activeSessionStatus else { return "Quiet" }
        switch activeSessionStatus {
        case .waitingApproval, .waitingQuestion: return "Needs you"
        case .running, .processing: return "Working"
        case .idle: return "Quiet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(needsAttention ? "Signal is hot" : (activeTaskCount > 0 ? "Work is moving" : "Signal is quiet"))
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Color.ciForeground)
                    Text(attentionSubtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.ciForeground.opacity(0.52))
                }
                Spacer(minLength: 12)
                Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "sparkle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(needsAttention ? .orange : Color.ciForeground.opacity(0.58))
                    .frame(width: 36, height: 36)
                    .background(
                        (needsAttention ? Color.orange : Color.ciForeground).opacity(needsAttention ? 0.16 : 0.07),
                        in: Circle()
                    )
            }

            HStack(spacing: 8) {
                CompanionSignalTile(
                    title: "\(approvalCount)",
                    subtitle: approvalCount == 1 ? "approval" : "approvals",
                    symbol: "checkmark.seal",
                    tint: approvalCount > 0 ? .orange : Color.ciForeground.opacity(0.55)
                )
                CompanionSignalTile(
                    title: "\(questionCount)",
                    subtitle: questionCount == 1 ? "question" : "questions",
                    symbol: "questionmark.bubble",
                    tint: questionCount > 0 ? Color(red: 0.34, green: 0.62, blue: 1.0) : Color.ciForeground.opacity(0.55)
                )
                CompanionSignalTile(
                    title: urgentTaskCount > 0 ? "\(urgentTaskCount) need you" : (activeTaskCount > 0 ? "\(activeTaskCount) active" : sessionTitle),
                    subtitle: connectionTitle,
                    symbol: urgentTaskCount > 0 ? "terminal.fill" : connectionSymbol,
                    tint: urgentTaskCount > 0 ? .orange : (connectionState == .connected ? .green : .orange)
                )
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(
                    needsAttention ? Color.orange.opacity(0.26) : Color.ciForeground.opacity(0.075),
                    lineWidth: needsAttention ? 1 : 0.5
                )
        )
        .shadow(
            color: (needsAttention ? Color.orange : Color.black).opacity(needsAttention ? 0.14 : 0.055),
            radius: needsAttention ? 22 : 16,
            y: needsAttention ? 10 : 7
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(needsAttention
            ? (remoteNeedsAttention
                ? "\(approvalCount) approvals, \(questionCount) questions, and \(urgentTaskCount) coding tasks need attention"
                : "A nearby session is waiting for you in Sessions.")
            : "No approvals, questions, or urgent coding tasks are waiting.")
        .accessibilityIdentifier("companion.signalBoard")
    }
}

private struct CompanionSignalTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: title.count > 3 ? 13 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ciForeground.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ciForeground.opacity(0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(10)
        .background(Color.ciForeground.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.ciForeground.opacity(0.055), lineWidth: 0.5)
        )
    }
}

private struct CompanionCommandBackground: View {
    var body: some View {
        ZStack {
            Color.ciBackground

            GeometryReader { proxy in
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: proxy.size.width * 0.72, height: proxy.size.width * 0.72)
                    .blur(radius: 80)
                    .offset(x: -proxy.size.width * 0.26, y: -proxy.size.height * 0.18)

                Circle()
                    .fill(Color.ciForeground.opacity(0.045))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.58)
                    .blur(radius: 72)
                    .offset(x: proxy.size.width * 0.54, y: proxy.size.height * 0.22)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct CompanionPresenceHeader: View {
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @AppStorage(CompanionFirst.flagKey) private var companionFirst = true

    var body: some View {
        HStack(spacing: 12) {
            CodeIslandPresenceMark()
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Code Island")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ciForeground)
                Text(presentation.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ciForeground.opacity(0.52))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Circle()
                .fill(presentation.isActive ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(10)
                .background(Color.ciForeground.opacity(0.055), in: Circle())
                .accessibilityLabel(presentation.isActive ? "Mac connected" : "Mac unavailable")

            Menu {
                Button {
                    connection.browsing ? connection.stop() : connection.start()
                } label: {
                    Label(
                        connection.browsing ? "Stop nearby discovery" : "Search nearby",
                        systemImage: connection.browsing ? "stop.circle" : "dot.radiowaves.left.and.right"
                    )
                }

                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }

                Toggle(isOn: $companionFirst) {
                    Label("Companion-first Tools", systemImage: "square.grid.2x2")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.ciForeground.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Connection and appearance")
            .accessibilityIdentifier("companion.presence.menu")
        }
        .padding(10)
        .frame(minHeight: 68)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.ciForeground.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.presence")
        .onChange(of: companionFirst) { _, _ in
            Task { await remoteApprovals.refreshHub() }
        }
    }

    private var presentation: CompanionConnectionPresentation {
        CompanionConnectionPresentation.resolve(
            localActivitySubtitle: remoteApprovals.state == .connected ? nil : localActivitySubtitle,
            localPeerName: connection.connectedPeer?.displayName,
            localBrowsing: connection.browsing,
            remoteState: remoteApprovals.state,
            remoteServerName: remoteApprovals.serverName
        )
    }

    private var localActivitySubtitle: String? {
        guard let state = connection.latestState else { return nil }
        return CompanionDisplayText.workspace(state.workspaceName)
            ?? CompanionDisplayText.tool(state.toolName)
    }
}

private struct CodeIslandPresenceMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.08), Color(white: 0.17)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay {
                VStack(spacing: 1) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: 14, height: 3)
                        .opacity(0.92)
                }
            }
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
        .frame(width: 50, height: 50)
    }
}

private struct CompanionActionDock: View {
    let destination: CommandCenterDestination
    let attentionCount: Int
    let select: (CommandCenterDestination) -> Void
    let capture: () -> Void
    let more: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    dockContent
                        .padding(6)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
                }
            } else {
                dockContent
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.ciForeground.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
        .shadow(color: Color.black.opacity(0.10), radius: 24, y: 10)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.actionDock")
    }

    private var dockContent: some View {
        HStack(spacing: 4) {
            destinationButton(.now)
            destinationButton(.sessions)

            Button(action: capture) {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(attentionCount == 0 ? Color.black : Color.ciForeground.opacity(0.72))
                        .frame(width: 30, height: 30)
                        .background(
                            attentionCount == 0 ? Color.orange : Color.ciForeground.opacity(0.08),
                            in: Circle()
                        )
                    Text("Capture")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Color.ciForeground.opacity(0.76))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion.capture")

            Button(action: more) {
                dockLabel(title: "Tools", symbol: "square.grid.2x2", selected: false)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion.more")
        }
    }

    private func destinationButton(_ item: CommandCenterDestination) -> some View {
        Button { select(item) } label: {
            ZStack(alignment: .topTrailing) {
                dockLabel(title: item.title, symbol: item.symbol, selected: destination == item)
                if item == .now, attentionCount > 0 {
                    Text("\(min(attentionCount, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.orange, in: Circle())
                        .offset(x: -4, y: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            item == .now && attentionCount > 0
                ? "Now, \(attentionCount) items need attention"
                : item.title
        )
        .accessibilityIdentifier("companion.destination.\(item.rawValue)")
    }

    private func dockLabel(title: String, symbol: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(selected ? Color.ciForeground : Color.ciForeground.opacity(0.56))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            selected ? Color.ciForeground.opacity(0.10) : Color.clear,
            in: Capsule()
        )
        .contentShape(Rectangle())
    }
}

// Pair 2: "While you were away" ledger. Renders recent terminal outcomes and
// live work from the task history the client already holds (no wire change).
private struct CompanionAwayLedger: View {
    let tasks: [RemoteTaskSummary]

    private var rows: [RemoteTaskSummary] {
        Array(
            tasks
                .filter { [.verified, .failed, .cancelled, .working].contains($0.state) }
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(4)
        )
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("While you were away")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.ciForeground)
                ForEach(rows, id: \.id) { task in
                    HStack(spacing: 10) {
                        Image(systemName: icon(task.state))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint(task.state))
                            .frame(width: 22, height: 22)
                            .background(tint(task.state).opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.ciForeground)
                                .lineLimit(1)
                            Text("\(task.workspaceName) · \(label(task.state))")
                                .font(.caption2)
                                .foregroundStyle(Color.ciForeground.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(task.updatedAt, style: .relative)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(Color.ciForeground.opacity(0.4))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityIdentifier("companion.awayLedger")
        }
    }

    private func icon(_ state: RemoteTaskState) -> String {
        switch state {
        case .verified: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "slash.circle"
        case .working: return "play.fill"
        default: return "circle"
        }
    }
    private func tint(_ state: RemoteTaskState) -> Color {
        switch state {
        case .verified: return .green
        case .failed: return .red
        case .cancelled: return Color.ciForeground.opacity(0.5)
        case .working: return .blue
        default: return .orange
        }
    }
    private func label(_ state: RemoteTaskState) -> String {
        switch state {
        case .verified: return "Verified"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .working: return "Running"
        default: return "Updated"
        }
    }
}

private struct CompanionTodayTimeline: View {
    let snapshot: PersonalHubSnapshot?
    let openSessions: () -> Void
    let openMore: () -> Void

    @Environment(\.openURL) private var openURL

    private var rows: [CommandTimelineRow] {
        guard let snapshot else { return [] }
        var result: [CommandTimelineRow] = []

        // Companion-first (B2-13): lead with agents, the reason to open Buddy,
        // then calendar as a single demoted row. Reminders is trimmed under the
        // flag, so it only appears in the legacy full-hub layout.
        if let agents = snapshot.modules.first(where: { $0.id == .agents }),
           let item = agents.items.first {
            result.append(.init(moduleID: .agents, item: item))
        }
        if let calendar = snapshot.modules.first(where: { $0.id == .calendar }),
           let item = calendar.items.first {
            result.append(.init(moduleID: .calendar, item: item))
        }
        if !CompanionFirst.isEnabled,
           let reminders = snapshot.modules.first(where: { $0.id == .reminders }),
           let item = reminders.items.first(where: { !$0.id.hasPrefix("list:") }) {
            result.append(.init(moduleID: .reminders, item: item))
        }
        return Array(result.prefix(3))
    }

    private var weatherSummary: String? {
        snapshot?.modules.first(where: { $0.id == .weather })?.summary
    }

    /// The Mac already composes an agents summary ("2 running · no decisions
    /// waiting"); reuse it so the empty state reports live work instead of
    /// repeating the headline. Falls back only when the module is absent.
    private var idleSummary: String {
        snapshot?.modules.first(where: { $0.id == .agents })?.summary
            ?? "Nothing has needed you recently."
    }

    private var hasAgentAttention: Bool {
        rows.contains { row in
            guard row.moduleID == .agents else { return false }
            return CompanionAgentAttention.needsAttention(
                flag: row.item.needsAttention,
                title: row.item.title,
                subtitle: row.item.subtitle,
                detail: row.item.detail
            )
        }
    }

    /// Attention outranks weather — R5 (finding I1). main returned weather
    /// first, which reintroduced the bug where "an agent is waiting" was
    /// unreachable whenever the Mac reported any weather. Keeps main's
    /// "Next: <upcoming item>" resting line for the idle case.
    private var headlineSubtitle: String {
        if hasAgentAttention {
            return "An agent is waiting for your decision."
        }
        if CompanionFirst.isEnabled {
            // Agent-first quiet hero (B2-13): report live agent work, not the
            // next meeting. idleSummary reuses the Mac's agents summary.
            return idleSummary
        }
        if let weatherSummary {
            return weatherSummary
        }
        if let first = rows.first {
            let subtitle = first.item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let subtitle, !subtitle.isEmpty {
                return "Next: \(first.item.title) · \(subtitle)"
            }
            return "Next: \(first.item.title)"
        }
        return "Nothing needs you right now."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                // The headline states the answer (R5, finding I1) rather than
                // the date, in main's refreshed type treatment.
                Text(hasAgentAttention ? "Needs you" : "All clear")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ciForeground)
                Text(headlineSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.ciForeground.opacity(0.56))
                    .lineLimit(2)
            }

            if snapshot == nil {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading your Mac")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ciForeground.opacity(0.72))
                }
                .frame(minHeight: 52)
            } else if rows.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.green)
                    // Says something the headline and subhead do not: how many
                    // sessions are quietly running, so "all clear" reads as
                    // informed rather than empty.
                    Text(idleSummary)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ciForeground.opacity(0.72))
                }
                .frame(minHeight: 52)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        timelineRow(row, isLast: index == rows.count - 1)
                    }
                }
            }

            Button(action: openMore) {
                Label("Open Tools", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ciForeground.opacity(0.62))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.ciForeground.opacity(0.075), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.now.overview")
    }

    private func timelineRow(_ row: CommandTimelineRow, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: row.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(row.tint)
                    .frame(width: 34, height: 34)
                    .background(row.tint.opacity(0.12), in: Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.ciForeground.opacity(0.10))
                        .frame(width: 1, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.item.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ciForeground.opacity(0.92))
                    .lineLimit(2)
                if let subtitle = row.item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.ciForeground.opacity(0.50))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let join = row.item.actions.first(where: { $0.id == "join" }),
               let deepLink = join.deepLink {
                Button("Join") { openURL(deepLink) }
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityIdentifier("companion.now.calendar.join")
            } else if row.moduleID == .agents, hasAgentAttention {
                Button("Review", action: openSessions)
                    .font(.subheadline.weight(.bold))
                    .buttonStyle(.bordered)
                    .tint(Color.ciForeground)
                    .accessibilityIdentifier("companion.now.agents.review")
            }
        }
        .frame(minHeight: 52)
    }
}

private struct CommandTimelineRow: Identifiable {
    let moduleID: PersonalHubModuleID
    let item: PersonalHubItem

    var id: String { "\(moduleID.rawValue):\(item.id)" }

    var symbol: String {
        item.symbol ?? PersonalHubCatalog.definition(for: moduleID).symbol
    }

    var tint: Color {
        let signal = [item.title, item.subtitle ?? "", item.detail ?? ""]
            .joined(separator: " ")
            .lowercased()
        if moduleID == .agents,
           signal.contains("approval") || signal.contains("question") || signal.contains("needs") || signal.contains("waiting") {
            return .orange
        }
        return Color.ciForeground.opacity(0.62)
    }
}
