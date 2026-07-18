import SwiftUI

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

private enum CommandCenterSheet: String, Identifiable {
    case more

    var id: String { rawValue }
}

struct CompanionCommandCenterView: View {
    let topPadding: CGFloat

    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var destination = CommandCenterDestination.now
    @State private var presentedSheet: CommandCenterSheet?
    @State private var showsCaptureChoices = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 24) {
                CompanionPresenceHeader()
                    .environmentObject(connection)
                    .environmentObject(remoteApprovals)

                switch destination {
                case .now:
                    nowContent
                case .sessions:
                    PersonalHubSessionsSurface()
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
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
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
        }
        .confirmationDialog("Capture", isPresented: $showsCaptureChoices) {
            Button("New task") { openQuickJot(.task) }
            Button("New note") { openQuickJot(.note) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add it through your private Mac connection.")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .more:
                NavigationStack {
                    ScrollView {
                        PersonalHubSurface()
                            .environmentObject(remoteApprovals)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 24)
                    }
                    .background(Color.ciBackground.ignoresSafeArea())
                    .navigationTitle("More")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { presentedSheet = nil }
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("companion.more.sheet")
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
        .onAppear {
            if remoteApprovals.highlightedHubModuleID != nil {
                presentedSheet = .more
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.commandCenter")
    }

    @ViewBuilder
    private var nowContent: some View {
        RemoteApprovalSurface()
            .environmentObject(remoteApprovals)

        if remoteApprovals.hasPairingCredential {
            CompanionTodayTimeline(
                snapshot: remoteApprovals.hubSnapshot,
                hasAttention: attentionCount > 0,
                openSessions: { select(.sessions) },
                openMore: { presentedSheet = .more }
            )
        }
    }

    private var attentionCount: Int {
        remoteApprovals.approvals.count + remoteApprovals.questions.count
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
}

private struct CompanionPresenceHeader: View {
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var remoteApprovals: RemoteApprovalClient
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        HStack(spacing: 12) {
            CompanionMascotView(
                source: connection.latestState?.source ?? "codex",
                status: connection.latestState?.status ?? .idle,
                size: 36
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CodeIsland")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.ciForeground)
                Text(presentation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.ciForeground.opacity(0.58))
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
        .frame(minHeight: 54)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.presence")
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
                        .foregroundStyle(Color.black)
                        .frame(width: 30, height: 30)
                        .background(Color.orange, in: Circle())
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
                dockLabel(title: "More", symbol: "square.grid.2x2", selected: false)
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
            Image(systemName: selected ? "\(symbol).fill" : symbol)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(selected ? Color.ciForeground : Color.ciForeground.opacity(0.56))
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            selected ? Color.ciForeground.opacity(0.085) : Color.clear,
            in: Capsule()
        )
        .contentShape(Rectangle())
    }
}

private struct CompanionTodayTimeline: View {
    let snapshot: PersonalHubSnapshot?
    let hasAttention: Bool
    let openSessions: () -> Void
    let openMore: () -> Void

    @Environment(\.openURL) private var openURL

    private var rows: [CommandTimelineRow] {
        guard let snapshot else { return [] }
        var result: [CommandTimelineRow] = []

        if let calendar = snapshot.modules.first(where: { $0.id == .calendar }),
           let item = calendar.items.first {
            result.append(.init(moduleID: .calendar, item: item))
        }
        if let reminders = snapshot.modules.first(where: { $0.id == .reminders }),
           let item = reminders.items.first(where: { !$0.id.hasPrefix("list:") }) {
            result.append(.init(moduleID: .reminders, item: item))
        }
        if let agents = snapshot.modules.first(where: { $0.id == .agents }),
           let item = agents.items.first {
            result.append(.init(moduleID: .agents, item: item))
        }
        return Array(result.prefix(3))
    }

    private var weatherSummary: String? {
        snapshot?.modules.first(where: { $0.id == .weather })?.summary
    }

    private var hasAgentAttention: Bool {
        rows.contains { row in
            guard row.moduleID == .agents else { return false }
            let signal = [row.item.title, row.item.subtitle ?? "", row.item.detail ?? ""]
                .joined(separator: " ")
                .lowercased()
            return signal.contains("approval")
                || signal.contains("question")
                || signal.contains("needs")
                || signal.contains("waiting")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Today")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.ciForeground)
                Text(weatherSummary ?? (hasAttention || hasAgentAttention
                    ? "An agent is waiting for your decision."
                    : "Nothing needs you right now."))
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Nothing needs you right now.")
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
                Label("View all modules", systemImage: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ciForeground.opacity(0.62))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
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
        switch moduleID {
        case .calendar: return .blue
        case .reminders: return .orange
        case .agents: return .purple
        default: return .secondary
        }
    }
}
