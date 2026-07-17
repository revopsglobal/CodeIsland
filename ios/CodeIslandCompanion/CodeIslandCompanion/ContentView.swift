import MultipeerConnectivity
import SwiftUI
import UIKit

private enum CodeIslandMotion {
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.65)
    static let micro = Animation.easeOut(duration: 0.12)
}

struct ContentView: View {
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        GeometryReader { proxy in
            // Content respects the safe area (no longer ignored); elements automatically avoid the status bar / notch / Home indicator.
            // The .background below ignores the safe area to fill the entire screen.
            ZStack(alignment: .top) {
                if proxy.size.width > proxy.size.height, let state = connection.latestState {
                    StandByIsland(state: state, availableSize: proxy.size)
                        .environmentObject(connection)
                        .environmentObject(liveActivity)
                } else {
                    PortraitIslandView(topPadding: 40)
                        .environmentObject(connection)
                        .environmentObject(liveActivity)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            }
            .onAppear {
                connection.start()
            }
            .onChange(of: connection.latestState?.sequence) { _, _ in
                guard liveActivity.isRunning, let state = connection.latestState else { return }
                liveActivity.startOrUpdate(with: state)
            }
            .animation(CodeIslandMotion.open, value: connection.connectedPeer)
            .animation(CodeIslandMotion.pop, value: connection.latestState?.status)
            .animation(CodeIslandMotion.micro, value: connection.browsing)
        }
        .background(Color.ciBackground.ignoresSafeArea())
        .preferredColorScheme(appearance.colorScheme)
        .accessibilityIdentifier("companion.root")
    }
}

private struct PortraitIslandView: View {
    let topPadding: CGFloat
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    private static let pendingAnchor = "companion.pendingCard"

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    CompactIslandBar()
                        .environmentObject(connection)

                    if let state = connection.latestState {
                        LiveIslandCard(state: state)
                            .environmentObject(connection)
                            .environmentObject(liveActivity)
                            .id(Self.pendingAnchor)
                            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))

                        if let personalStatus = state.personalStatus, !personalStatus.isEmpty {
                            PersonalStatusStrip(status: personalStatus)
                                .transition(.blurFade.combined(with: .move(edge: .top)))
                        }

                        MessageStrip(messages: state.messages)
                    } else {
                        DiscoveryIsland()
                            .environmentObject(connection)
                            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))

                        DiscoveryFill()
                    }

                    if let error = connection.lastError {
                        DiagnosticStrip(message: error)
                            .transition(.blurFade.combined(with: .move(edge: .top)))
                    }

                    if let error = liveActivity.lastError {
                        LiveActivityDiagnosticStrip(message: error)
                            .environmentObject(liveActivity)
                            .transition(.blurFade.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.top, topPadding)
                .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 20))
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .accessibilityIdentifier("companion.scroll")
            .onChange(of: connection.latestState?.pendingAction) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    scroller.scrollTo(Self.pendingAnchor, anchor: .top)
                }
            }
            }
        }
    }
}

private struct PrimaryMessageView: View {
    let state: CompanionStatePayload

    var body: some View {
        let text = state.question?.question
            ?? CompanionDisplayText.message(state.messages.last?.text)
            ?? "No new messages"

        MorphText(
            text: text,
            font: .system(size: 16, weight: .medium),
            color: .ciForeground.opacity(state.messages.isEmpty && state.question == nil ? 0.55 : 0.86),
            lineLimit: state.question == nil ? 5 : 3,
            markdown: true
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MetadataChipRow: View {
    let workspaceName: String?
    let toolName: String?

    private var workspaceText: String? {
        CompanionDisplayText.workspace(workspaceName)
    }

    private var toolText: String? {
        CompanionDisplayText.tool(toolName)
    }

    var body: some View {
        if workspaceText != nil || toolText != nil {
            HStack(spacing: 8) {
                if let workspaceText {
                    TinyChip(icon: "folder", text: workspaceText)
                }
                if let toolText {
                    TinyChip(icon: "hammer", text: toolText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct QuestionOptionsView: View {
    let question: CompanionQuestionPayload
    @EnvironmentObject private var connection: CompanionConnection

    @State private var selected: Set<Int> = []
    @State private var showOther = false
    @State private var textInput = ""

    private let accent = Color(red: 0.38, green: 0.68, blue: 1.0)

    var body: some View {
        if question.options.isEmpty {
            // Free-text question: type and submit directly
            VStack(spacing: 8) {
                answerField(placeholder: "Type your answer")
                submitButton(title: "Submit answer", enabled: !trimmed.isEmpty) {
                    connection.sendAnswer(trimmed)
                }
            }
        } else if question.allowsMultipleSelection {
            LazyVStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(index: index, option: option, multiSelect: true)
                }
                otherToggleRow
                if showOther {
                    answerField(placeholder: "Other (type here)")
                }
                submitButton(title: "Submit selection", enabled: canSubmitMulti) {
                    connection.sendAnswer(multiAnswer)
                }
            }
        } else {
            LazyVStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(index: index, option: option, multiSelect: false)
                }
                otherToggleRow
                if showOther {
                    VStack(spacing: 8) {
                        answerField(placeholder: "Other (type here)")
                        submitButton(title: "Submit", enabled: !trimmed.isEmpty) {
                            connection.sendAnswer(trimmed)
                        }
                    }
                }
            }
        }
    }

    private var trimmed: String {
        textInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitMulti: Bool {
        !selected.isEmpty || (showOther && !trimmed.isEmpty)
    }

    // Multi-select answers match the Mac notch: selected option labels are sorted by index and joined with ", ", then the "Other" text is appended at the end.
    private var multiAnswer: String {
        var parts = selected.sorted().compactMap { question.options.indices.contains($0) ? question.options[$0] : nil }
        if showOther && !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func optionRow(index: Int, option: String, multiSelect: Bool) -> some View {
        let isSelected = selected.contains(index)
        Button {
            if multiSelect {
                if isSelected { selected.remove(index) } else { selected.insert(index) }
            } else {
                connection.sendAnswer(option)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if multiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? accent : .ciForeground.opacity(0.4))
                        .frame(width: 24, alignment: .leading)
                } else {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .frame(width: 24, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.ciForeground.opacity(0.86))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if question.descriptions.indices.contains(index) {
                        Text(question.descriptions[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.ciForeground.opacity(0.45))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciForeground.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? accent.opacity(0.5) : Color.ciForeground.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private var otherToggleRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showOther.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showOther ? "chevron.down" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 24, alignment: .leading)
                Text("Other…")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.ciForeground.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciForeground.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func answerField(placeholder: String) -> some View {
        TextField("", text: $textInput, prompt: Text(placeholder).foregroundColor(.ciForeground.opacity(0.4)), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.ciForeground)
            .lineLimit(1...4)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.ciForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ciForeground.opacity(0.1)))
            .accessibilityIdentifier("companion.question.textField")
    }

    private func submitButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? .black : .ciForeground.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(enabled ? accent : Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("companion.question.submit")
    }
}

private struct DiscoveryFill: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(spacing: 12) {
            DividerLine()
                .padding(.top, 2)

            Text("Keep iPhone and Mac on the same network and CodeIsland will keep the current status in sync.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.ciForeground.opacity(0.42))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            IslandButton(
                title: "Enter demo mode",
                icon: "play.rectangle.fill",
                tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                accessibilityIdentifier: "companion.enterDemoMode"
            ) {
                connection.enterDemoMode()
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct CompactIslandBar: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        HStack(spacing: 8) {
            CompanionMascotView(source: connection.latestState?.source ?? "codex", status: compactStatus, size: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                MorphText(
                    text: connection.latestState?.source.uppercased() ?? "CODEISLAND",
                    font: .system(size: 12, weight: .black, design: .rounded),
                    color: .ciForeground
                )
                MorphText(
                    text: compactSubtitle,
                    font: .system(size: 10, weight: .medium, design: .monospaced),
                    color: .ciForeground.opacity(0.52)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Spacer()

            ConnectionDot(active: connection.connectedPeer != nil, browsing: connection.browsing)

            Button {
                connection.browsing ? connection.stop() : connection.start()
            } label: {
                Image(systemName: connection.browsing ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.ciForeground.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(connection.browsing ? "Stop searching for Mac" : "Search for Mac")
            .accessibilityIdentifier("companion.search.toggle")

            AppearanceMenu()
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 46)
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
    }

    private var compactStatus: CompanionStatus {
        connection.latestState?.status ?? (connection.browsing ? .processing : .idle)
    }

    private var compactSubtitle: String {
        if let state = connection.latestState {
            if let toolName = state.toolName, !toolName.isEmpty {
                return CompanionDisplayText.tool(toolName) ?? toolName
            }
            if let workspaceName = state.workspaceName, !workspaceName.isEmpty {
                return CompanionDisplayText.workspace(workspaceName) ?? workspaceName
            }
            return state.status.label
        }
        if let peer = connection.connectedPeer {
            return peer.displayName
        }
        return connection.browsing ? "Searching" : "Offline"
    }
}

private struct LiveIslandCard: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    MorphText(
                        text: state.source.isEmpty ? "CodeIsland" : state.source.uppercased(),
                        font: .system(size: 15, weight: .bold, design: .rounded),
                        color: .ciForeground
                    )
                    MorphText(
                        text: CompanionDisplayText.subtitle(
                            workspaceName: state.workspaceName,
                            toolName: state.toolName,
                            fallback: "Mac connected"
                        ),
                        font: .system(size: 12, weight: .medium),
                        color: .ciForeground.opacity(0.58)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 10)

                if state.pendingAction != nil {
                    StatusPill(status: state.status)
                } else {
                    HeaderStatusDot(status: state.status)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            DividerLine()

            VStack(alignment: .leading, spacing: state.question == nil ? 14 : 10) {
                PrimaryMessageView(state: state)

                MetadataChipRow(workspaceName: state.workspaceName, toolName: state.toolName)

                if let question = state.question {
                    QuestionPromptCard(question: question)
                        .environmentObject(connection)
                        .transition(.blurFade.combined(with: .move(edge: .top)))
                }

                CommandRow(state: state)
                    .environmentObject(connection)
                    .environmentObject(liveActivity)
            }
            .padding(14)
            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(pendingTint ?? Color.ciForeground.opacity(0.08), lineWidth: pendingTint == nil ? 1 : 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CodeIsland status")
        .accessibilityIdentifier("companion.statusCard")
    }

    // When pending, outline and glow the card: approval = orange, question = blue.
    private var pendingTint: Color? {
        switch state.pendingAction {
        case .approval: return .orange
        case .question: return Color(red: 0.38, green: 0.68, blue: 1.0)
        case nil: return nil
        }
    }
}

private struct QuestionPromptCard: View {
    let question: CompanionQuestionPayload
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("?")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.38, green: 0.68, blue: 1.0).opacity(0.14), in: Capsule())
                }
                Spacer()
                if question.total > 1 {
                    Text("\(question.index)/\(question.total)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.ciForeground.opacity(0.48))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.ciForeground.opacity(0.08), in: Capsule())
                }
            }

            Text(CompanionDisplayText.inlineMarkdown(question.question))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.9))
                .lineLimit(5)

            QuestionOptionsView(question: question)
                .environmentObject(connection)
                .id("\(question.index)/\(question.total)·\(question.question)")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ciForeground.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.24)))
        .accessibilityIdentifier("companion.questionCard")
    }
}

private struct DiscoveryIsland: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    MorphText(
                        text: connection.connectedPeer == nil ? "Waiting for Mac" : "Mac connected",
                        font: .system(size: 15, weight: .bold, design: .rounded),
                        color: .ciForeground
                    )
                    MorphText(
                        text: subtitle,
                        font: .system(size: 12, weight: .medium),
                        color: .ciForeground.opacity(0.58)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                ConnectionDot(active: connection.connectedPeer != nil, browsing: connection.browsing)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            DividerLine()

            VStack(spacing: 10) {
                if connection.discoveredPeers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.green)
                        Text(connection.browsing ? "Searching for nearby CodeIsland" : "Search stopped")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.ciForeground.opacity(0.72))
                        Spacer()
                    }
                    .frame(minHeight: 48)
                } else {
                    ForEach(connection.discoveredPeers, id: \.self) { peer in
                        Button {
                            connection.connect(to: peer)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "macbook")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                    .frame(width: 32, height: 32)
                                    .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(peer.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.ciForeground)

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.ciForeground.opacity(0.5))
                            }
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
        .accessibilityIdentifier("companion.discoveryCard")
    }

    private var subtitle: String {
        if let peer = connection.connectedPeer {
            return peer.displayName
        }
        if connection.discoveredPeers.isEmpty {
            return connection.browsing ? "Broadcasting handshake" : "Tap the top-right to keep searching"
        }
        return "Found \(connection.discoveredPeers.count) devices"
    }
}

private struct CommandRow: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(spacing: 8) {
            if connection.isDemoMode {
                HStack(spacing: 8) {
                    IslandButton(
                        title: "Cycle demo state",
                        icon: "arrow.triangle.2.circlepath",
                        tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                        accessibilityIdentifier: "companion.demo.nextState"
                    ) {
                        connection.cycleDemoState()
                    }
                    IslandButton(
                        title: "Exit demo",
                        icon: "xmark",
                        tint: .red,
                        accessibilityIdentifier: "companion.demo.exit"
                    ) {
                        connection.exitDemoMode()
                    }
                }
            }

            if state.pendingAction == .question {
                HStack(spacing: 8) {
                    IslandButton(
                        title: "Answer on Mac",
                        icon: "arrow.up.forward.app.fill",
                        tint: Color(red: 0.35, green: 0.85, blue: 0.45),
                        accessibilityIdentifier: "companion.command.focus"
                    ) {
                        connection.send(.focus)
                    }
                    IslandButton(
                        title: "Skip",
                        icon: "forward.fill",
                        tint: .orange,
                        accessibilityIdentifier: "companion.command.skip"
                    ) {
                        connection.send(.skipCurrentQuestion)
                    }
                }
                .transition(.blurFade.combined(with: .move(edge: .top)))

                LiveActivityInlineButton(state: state)
            } else {
                HStack(spacing: 8) {
                    IslandButton(
                        title: "Open Mac session",
                        icon: "arrow.up.forward.app.fill",
                        tint: Color(red: 0.35, green: 0.85, blue: 0.45),
                        accessibilityIdentifier: "companion.command.focus"
                    ) {
                        connection.send(.focus)
                    }

                    IslandButton(
                        title: liveActivity.isRunning ? "Update Live Activity" : "Start Live Activity",
                        icon: liveActivity.isRunning ? "arrow.clockwise" : "bolt.horizontal.fill",
                        tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                        accessibilityIdentifier: "companion.liveActivity.primaryButton"
                    ) {
                        liveActivity.startOrUpdate(with: state)
                    }
                }

                if state.pendingAction == .approval {
                    HStack(spacing: 8) {
                        IslandButton(title: "Approve", icon: "checkmark", tint: .orange, accessibilityIdentifier: "companion.command.approve") {
                            connection.send(.approveCurrentPermission)
                        }
                        IslandButton(title: "Deny", icon: "xmark", tint: .red, accessibilityIdentifier: "companion.command.deny") {
                            connection.send(.denyCurrentPermission)
                        }
                    }
                    .transition(.blurFade.combined(with: .move(edge: .top)))
                }

                if liveActivity.isRunning {
                    LiveActivityInlineButton(state: state)
                }
            }
        }
    }
}

private struct LiveActivityInlineButton: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        Button {
            if liveActivity.isRunning {
                liveActivity.stop()
            } else {
                liveActivity.startOrUpdate(with: state)
            }
        } label: {
            Label(
                liveActivity.isRunning ? "Stop Live Activity" : "Sync to Live Activity",
                systemImage: liveActivity.isRunning ? "stop.circle.fill" : "bolt.horizontal.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(liveActivity.isRunning ? .ciForeground.opacity(0.62) : Color(red: 0.25, green: 0.76, blue: 1.0).opacity(0.86))
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companion.liveActivity.inlineButton")
    }
}

private struct MessageStrip: View {
    let messages: [CompanionMessagePreview]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                    Text("Recent activity")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.ciForeground.opacity(0.45))
                    .textCase(.uppercase)
                Rectangle()
                    .fill(.ciForeground.opacity(0.10))
                    .frame(height: 0.5)
            }

            if messages.isEmpty {
                HStack(spacing: 8) {
                    PulseDot(status: .idle)
                    Text("Waiting for the next synced message")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.ciForeground.opacity(0.5))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.suffix(3))) { message in
                        HStack(alignment: .top, spacing: 12) {
                            Text(message.role.label)
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(message.role == .user ? Color.ciSurface : Color.ciForeground)
                                .frame(width: 42, height: 28)
                                .background(message.role == .user ? Color.ciForeground.opacity(0.86) : Color.ciForeground.opacity(0.12), in: Capsule())

                            Text(CompanionDisplayText.messageMarkdown(CompanionDisplayText.message(message.text) ?? message.text, isUser: message.role == .user))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.ciForeground.opacity(0.76))
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.blurFade.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ciForeground.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ciForeground.opacity(0.06)))
        .accessibilityIdentifier("companion.messages")
    }
}

// Landscape hero multi-turn transcript for the primary session, aligned with the notch ChatMessageRow ($ assistant / > user).
// iPhone (compact landscape) shows the latest 1, iPad shows the latest 3.
private struct HeroTranscript: View {
    let messages: [CompanionMessagePreview]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var maxMessages: Int { sizeClass == .compact ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(messages.suffix(maxMessages).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 6) {
                    Text(message.role == .user ? ">" : "$")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(message.role == .user
                            ? Color(red: 0.3, green: 0.85, blue: 0.4)
                            : Color(red: 0.85, green: 0.47, blue: 0.34))
                    Text(CompanionDisplayText.messageMarkdown(
                        CompanionDisplayText.message(message.text) ?? message.text,
                        isUser: message.role == .user
                    ))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.ciForeground.opacity(0.82))
                    .lineLimit(message.role == .user ? 1 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Greg's compact personal signals. Agent sessions remain the primary Buddy
/// surface; this card appears only when the Mac has something useful to show.
private struct PersonalStatusStrip: View {
    let status: CompanionPersonalStatus
    var compact = false

    private var visibleDevices: ArraySlice<CompanionDeviceBatteryStatus> {
        status.devices.prefix(compact ? 2 : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                Text("PERSONAL")
                    .font(.system(size: compact ? 10 : 11, weight: .black, design: .rounded))
                    .tracking(1.2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.ciForeground.opacity(0.5))

            if let download = status.download {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: compact ? 18 : 21, weight: .semibold))
                        .foregroundStyle(Color.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(download.name)
                                .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.ciForeground.opacity(0.88))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(downloadDetail(download))
                                .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.ciForeground.opacity(0.52))
                        }
                        if let progress = download.progress {
                            ProgressView(value: progress)
                                .tint(.blue)
                        }
                    }
                }
            } else if let completed = status.recentDownloadCompleted {
                Label("Downloaded \(completed)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }

            if !visibleDevices.isEmpty {
                HStack(spacing: 7) {
                    ForEach(Array(visibleDevices)) { device in
                        HStack(spacing: 5) {
                            Image(systemName: batterySymbol(device.percent))
                            Text(device.name)
                                .lineLimit(1)
                            Text("\(min(max(device.percent, 0), 100))%")
                                .fontWeight(.black)
                        }
                        .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(device.percent <= 20 ? Color.orange : Color.ciForeground.opacity(0.72))
                        .padding(.horizontal, compact ? 7 : 9)
                        .padding(.vertical, compact ? 5 : 6)
                        .background(Color.ciForeground.opacity(0.07), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(compact ? 11 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.ciForeground.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.ciForeground.opacity(0.07))
        )
        .accessibilityIdentifier("companion.personalStatus")
    }

    private func downloadDetail(_ download: CompanionDownloadStatus) -> String {
        if let progress = download.progress {
            return "\(Int((progress * 100).rounded()))%"
        }
        return ByteCountFormatter.string(fromByteCount: download.bytesReceived, countStyle: .file)
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ...10: return "battery.0percent"
        case ...35: return "battery.25percent"
        case ...60: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

private struct StandByIsland: View {
    let state: CompanionStatePayload
    let availableSize: CGSize
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    private var sessions: [CompanionSessionPreview] {
        standbySessions(for: state)
    }

    private var activeCount: Int {
        sessions.filter { $0.status != .idle }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    CompanionMascotView(source: state.source, status: state.status, size: 78)

                    VStack(alignment: .leading, spacing: 5) {
                        MorphText(
                            text: sessions.count > 1 ? "CODE ISLAND" : (state.source.isEmpty ? "CODEISLAND" : state.source.uppercased()),
                            font: .system(size: 32, weight: .black, design: .rounded),
                            color: .ciForeground
                        )
                        MorphText(
                            text: sessions.count > 1 ? "\(sessions.count) sessions · \(activeCount) active" : state.status.label,
                            font: .system(size: 22, weight: .semibold, design: .rounded),
                            color: activeCount > 0 ? .green : statusColor(state.status)
                        )
                    }

                    Spacer(minLength: 12)

                    AppearanceMenu()
                }

                if !state.messages.isEmpty {
                    // Primary-session multi-turn transcript (aligned with the notch: $ assistant / > user)
                    HeroTranscript(messages: state.messages)
                } else {
                    MorphText(
                        text: CompanionDisplayText.workspace(state.workspaceName) ?? "CodeIsland connected",
                        font: .system(size: 24, weight: .medium, design: .rounded),
                        color: .ciForeground.opacity(0.82),
                        lineLimit: 4
                    )
                    .minimumScaleFactor(0.72)
                }

                HStack(spacing: 10) {
                    if let workspaceText = CompanionDisplayText.workspace(state.workspaceName) {
                        TinyChip(icon: "folder", text: workspaceText)
                    }
                    if let toolText = CompanionDisplayText.tool(state.toolName) {
                        TinyChip(icon: "hammer", text: toolText)
                    }
                }

                if let personalStatus = state.personalStatus, !personalStatus.isEmpty {
                    PersonalStatusStrip(status: personalStatus, compact: true)
                }
            }
            .frame(maxWidth: sessions.count > 1 ? availableSize.width * 0.34 : .infinity, alignment: .leading)
            .padding(24)

            DividerLine(vertical: true)

            if sessions.count > 1 {
                StandBySessionBoard(sessions: sessions, activeCount: activeCount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(20)
            } else {
                VStack(spacing: 10) {
                    IconIslandButton(icon: "arrow.up.forward.app.fill", tint: Color(red: 0.35, green: 0.85, blue: 0.45)) {
                        connection.send(.focus)
                    }
                    IconIslandButton(icon: liveActivity.isRunning ? "arrow.clockwise" : "bolt.horizontal.fill", tint: Color(red: 0.25, green: 0.76, blue: 1.0)) {
                        liveActivity.startOrUpdate(with: state)
                    }
                    if state.pendingAction != nil {
                        IconIslandButton(icon: "checkmark", tint: .orange) {
                            connection.send(.approveCurrentPermission)
                        }
                        IconIslandButton(icon: "xmark", tint: .red) {
                            connection.send(.denyCurrentPermission)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 260,
            maxHeight: .infinity
        )
    }
}

private enum StandByGrouping: CaseIterable {
    case none, status, cli

    var label: String {
        switch self {
        case .none: return "All"
        case .status: return "By status"
        case .cli: return "By CLI"
        }
    }

    var next: StandByGrouping {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

private struct StandByGroup: Identifiable {
    let id: String
    let items: [CompanionSessionPreview]
}

private struct StandBySessionBoard: View {
    let sessions: [CompanionSessionPreview]
    let activeCount: Int
    @State private var grouping: StandByGrouping = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedSessions) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if grouping != .none {
                                Text("\(group.id) · \(group.items.count)")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(.ciForeground.opacity(0.5))
                            }
                            ForEach(group.items) { session in
                                StandBySessionRow(session: session)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("companion.standby.scroll")
        }
        .accessibilityIdentifier("companion.standby.board")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Sessions")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.ciForeground)
            StandByCountBadge(count: sessions.count, activeCount: activeCount)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { grouping = grouping.next }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.3.group")
                    Text(grouping.label)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.ciForeground.opacity(0.72))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.ciForeground.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion.standby.groupToggle")
        }
    }

    private var groupedSessions: [StandByGroup] {
        switch grouping {
        case .none:
            return [StandByGroup(id: "All", items: sessions)]
        case .status:
            let order: [CompanionStatus] = [.waitingApproval, .waitingQuestion, .running, .processing, .idle]
            return order.compactMap { status in
                let items = sessions.filter { $0.status == status }
                return items.isEmpty ? nil : StandByGroup(id: status.label, items: items)
            }
        case .cli:
            let grouped = Dictionary(grouping: sessions) { $0.source.isEmpty ? "CODEISLAND" : $0.source.uppercased() }
            return grouped.keys.sorted().map { StandByGroup(id: $0, items: grouped[$0] ?? []) }
        }
    }
}

// Multi-turn transcript inside the session card (compact version), $ assistant / > user, with markdown.
// iPhone (compact landscape) shows only the latest 1 per card, iPad shows the latest 3.
private struct SessionTranscript: View {
    let messages: [CompanionMessagePreview]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var maxMessages: Int { sizeClass == .compact ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(messages.suffix(maxMessages).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 5) {
                    Text(message.role == .user ? ">" : "$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(message.role == .user
                            ? Color(red: 0.3, green: 0.85, blue: 0.4)
                            : Color(red: 0.85, green: 0.47, blue: 0.34))
                    Text(CompanionDisplayText.messageMarkdown(
                        CompanionDisplayText.message(message.text) ?? message.text,
                        isUser: message.role == .user
                    ))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.ciForeground.opacity(0.66))
                    .lineLimit(message.role == .user ? 1 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct StandBySessionRow: View {
    let session: CompanionSessionPreview
    var messageLineLimit: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CompanionMascotView(source: session.source, status: session.status, size: 32)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                // Identity row: project name (far left, colored by status) + #shortId … time-ago + tool badge on the right
                HStack(spacing: 6) {
                    Text(sessionName)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(statusNameColor)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if let shortId = shortSessionId {
                        Text("#\(shortId)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.ciForeground.opacity(0.4))
                            .fixedSize()
                    }
                    Spacer(minLength: 6)
                    SessionTag(standbyTimeAgo(session.updatedAt))
                    HStack(spacing: 3) {
                        CompanionMascotView(source: session.source, status: session.status, size: 12)
                        Text(CompanionDisplayText.source(session.source))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.ciForeground.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.ciForeground.opacity(0.1)))
                    .fixedSize()
                }

                // Multi-turn transcript (the latest few per session, $ assistant / > user); falls back to a single message when an older Mac lacks this data.
                if !session.messages.isEmpty {
                    SessionTranscript(messages: session.messages)
                } else if let message = CompanionDisplayText.message(session.message) {
                    Text(CompanionDisplayText.messageMarkdown(message, isUser: false))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.ciForeground.opacity(0.6))
                        .lineLimit(messageLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Work indicator row: $ tool / $ thinking (aligned with the bottom of the notch SessionCard)
                if session.status != .idle {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                        if let tool = CompanionDisplayText.tool(session.toolName) {
                            Text(tool)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.ciForeground.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            ThinkingLabel()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((highlightTint ?? Color.ciForeground).opacity(highlightTint == nil ? 0.055 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(highlightTint?.opacity(0.55) ?? Color.ciForeground.opacity(0.07), lineWidth: highlightTint == nil ? 1 : 1.5))
        .accessibilityIdentifier("companion.standby.sessionRow")
    }

    // Name colored by status, aligned with the notch SessionCard: running/processing = green, pending = orange, idle = white.
    private var statusNameColor: Color {
        switch session.status {
        case .processing, .running: return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval, .waitingQuestion: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .idle: return .ciForeground
        }
    }

    // Short session id (strip hyphens, take the last 4), aligned with the notch #id.
    private var shortSessionId: String? {
        guard let id = session.sessionId else { return nil }
        let clean = id.replacingOccurrences(of: "-", with: "")
        return clean.isEmpty ? nil : String(clean.suffix(4))
    }

    // Session name: prefer the project/workspace name, fall back to the source (aligned with the notch, which uses the project name as the title).
    private var sessionName: String {
        CompanionDisplayText.workspace(session.workspaceName)
            ?? (session.source.isEmpty ? "CODEISLAND" : session.source.uppercased())
    }

    // Pending-state highlight: approval = orange, question = blue; nothing else is highlighted.
    private var highlightTint: Color? {
        switch session.status {
        case .waitingApproval: return .orange
        case .waitingQuestion: return Color(red: 0.38, green: 0.68, blue: 1.0)
        default: return nil
        }
    }
}

// Small tag capsule, aligned with the notch SessionCard's SessionTag.
private struct SessionTag: View {
    let text: String
    var color: Color = .ciForeground.opacity(0.7)

    init(_ text: String, color: Color = .ciForeground.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
    }
}

// "Thinking" label: a band of highlight sweeps horizontally across the text on a loop (patrol sweep).
private struct ThinkingLabel: View {
    var text: String = "thinking"
    private let font = Font.system(size: 12, weight: .medium, design: .monospaced)
    private let period: TimeInterval = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = (timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period)) / period
            Text(text)
                .font(font)
                .foregroundStyle(.ciForeground.opacity(0.35))
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let band = max(22, width * 0.5)
                        LinearGradient(
                            colors: [.clear, .ciForeground.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: phase * (width + band) - band)
                    }
                    .mask(Text(text).font(font))
                    .allowsHitTesting(false)
                }
        }
        .fixedSize()
    }
}

// Relative time, aligned with the notch timeAgo format.
private func standbyTimeAgo(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 60 { return "<1m" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}

private struct StandByCountBadge: View {
    let count: Int
    let activeCount: Int

    var body: some View {
        Text(activeCount > 0 ? "\(activeCount) active" : "\(count) total")
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(activeCount > 0 ? .green : .ciForeground.opacity(0.64))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((activeCount > 0 ? Color.green : Color.ciForeground).opacity(0.12), in: Capsule())
    }
}

private func standbySessions(for state: CompanionStatePayload) -> [CompanionSessionPreview] {
    guard !state.sessions.isEmpty else {
        return [
            CompanionSessionPreview(
                sessionId: state.sessionId,
                source: state.source,
                status: state.status,
                toolName: state.toolName,
                workspaceName: state.workspaceName,
                message: state.question?.question ?? state.messages.last?.text,
                updatedAt: state.updatedAt
            )
        ]
    }
    // Pending items auto-focus: sorted by status priority (approval > question > running > processing > idle), ties broken by most recent update.
    return state.sessions.sorted { lhs, rhs in
        if lhs.status.priority != rhs.status.priority {
            return lhs.status.priority > rhs.status.priority
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

// Appearance switcher menu: follow system / light / dark.
private struct AppearanceMenu: View {
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
        } label: {
            Image(systemName: (AppAppearance(rawValue: appearanceRaw) ?? .system).icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.86))
                .frame(width: 38, height: 38)
                .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Appearance")
        .accessibilityIdentifier("companion.appearance.menu")
    }
}

private struct MorphText: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .ciForeground
    var lineLimit: Int? = 1
    var markdown: Bool = false

    @State private var displayed: String
    @State private var blur: CGFloat = 0
    @State private var generation = 0

    init(text: String, font: Font = .system(size: 12), color: Color = .ciForeground, lineLimit: Int? = 1, markdown: Bool = false) {
        self.text = text
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.markdown = markdown
        _displayed = State(initialValue: text)
    }

    private var renderedText: Text {
        markdown ? Text(CompanionDisplayText.messageMarkdown(displayed, isUser: false)) : Text(displayed)
    }

    var body: some View {
        renderedText
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .blur(radius: blur * 4)
            .opacity(1 - blur * 0.15)
            .animation(CodeIslandMotion.micro, value: blur)
            .onChange(of: text) { _, newText in
                guard newText != displayed else { return }
                // Streaming increments (prefix growing/shrinking) update directly, with no blur morph,
                // to avoid constant flicker during per-character updates. Only a full content swap gets the morph transition.
                if newText.hasPrefix(displayed) || displayed.hasPrefix(newText) {
                    generation += 1
                    displayed = newText
                    if blur != 0 { withAnimation(.easeOut(duration: 0.12)) { blur = 0 } }
                    return
                }
                generation += 1
                let current = generation
                withAnimation(.easeOut(duration: 0.1)) { blur = 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard current == generation else { return }
                    displayed = newText
                    withAnimation(.easeOut(duration: 0.15)) { blur = 0 }
                }
            }
    }
}

private struct IslandShellShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
    }
}

private struct DividerLine: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Color.ciForeground.opacity(0.12))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

private struct StatusPill: View {
    let status: CompanionStatus

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(status: status)
            Text(status.shortLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.ciForeground.opacity(0.08), in: Capsule())
    }
}

private struct HeaderStatusDot: View {
    let status: CompanionStatus

    var body: some View {
        PulseDot(status: status)
            .frame(width: 30, height: 30)
            .background(Color.ciForeground.opacity(0.07), in: Capsule())
            .accessibilityLabel(status.label)
    }
}

private struct PulseDot: View {
    let status: CompanionStatus

    var body: some View {
        TimelineView(.animation) { timeline in
            let scale = pulseScale(timeline.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(statusColor(status).opacity(0.5), lineWidth: 1)
                        .scaleEffect(scale)
                        .opacity(max(0, 1.2 - scale))
                }
        }
        .frame(width: 14, height: 14)
    }

    private func pulseScale(_ phase: TimeInterval) -> CGFloat {
        switch status {
        case .idle:
            return 1
        case .processing, .running:
            return 1 + CGFloat((sin(phase * 4.2) + 1) * 0.28)
        case .waitingApproval, .waitingQuestion:
            return 1 + CGFloat((sin(phase * 7.0) + 1) * 0.42)
        }
    }
}

private struct ConnectionDot: View {
    let active: Bool
    let browsing: Bool

    var body: some View {
        PulseDot(status: active ? .running : (browsing ? .processing : .idle))
        .frame(width: 30, height: 30)
        .background(Color.ciForeground.opacity(0.08), in: Capsule())
        .accessibilityLabel(active ? "Mac connected" : (browsing ? "Searching for Mac" : "Mac not connected"))
    }
}

private struct TinyChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.ciForeground.opacity(0.64))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.ciForeground.opacity(0.07), in: Capsule())
    }
}

private struct IslandButton: View {
    let title: String
    let icon: String
    let tint: Color
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(tint == .orange ? .black : tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(buttonBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.42)))
        }
        .buttonStyle(.plain)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var buttonBackground: Color {
        tint == .orange ? .orange : tint.opacity(0.20)
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

private struct IconIslandButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint == .orange ? .black : tint)
                .frame(width: 52, height: 52)
                .background(tint == .orange ? .orange : tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

private struct DiagnosticStrip: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

private struct LiveActivityDiagnosticStrip: View {
    let message: String
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "bolt.horizontal.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 1.0))

            Button {
                liveActivity.stopAll()
            } label: {
                Label("Clear existing Live Activities and retry", systemImage: "trash")
                    .font(.caption.weight(.bold))
                    // This notice card is fixed to a deep-blue background (consistent across both themes); its text stays light to preserve contrast.
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.10, green: 0.18, blue: 0.24)))
    }
}

private struct BlurFadeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 5 : 0)
            .opacity(active ? 0 : 1)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(active: true),
            identity: BlurFadeModifier(active: false)
        )
    }
}

private func statusColor(_ status: CompanionStatus) -> Color {
    switch status {
    case .idle:
        return Color(red: 0.55, green: 0.60, blue: 0.68)
    case .processing, .running:
        return Color(red: 0.30, green: 0.85, blue: 0.40)
    case .waitingApproval, .waitingQuestion:
        return Color(red: 1.0, green: 0.55, blue: 0.0)
    }
}

#Preview {
    ContentView()
        .environmentObject(CompanionConnection())
        .environmentObject(LiveActivityController())
}

// MARK: - Appearance preference (follow system / light / dark)

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Follow system"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// Passed to `.preferredColorScheme`; nil means follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// AppStorage key, shared by the App and all views.
let appAppearanceStorageKey = "appAppearance"

// MARK: - Adaptive theme colors
//
// Uses a dynamic UIColor that resolves light/dark automatically, so views don't need to inject the environment;
// colors switch automatically with the effective appearance decided by `.preferredColorScheme`.
// Dark keeps the original "Dynamic Island" pure-black look; light is a warm, eye-friendly off-white beige.
//
// Defined on `ShapeStyle where Self == Color`: dot syntax resolves in ShapeStyle positions like `.foregroundStyle(.ciX)`
// / `.fill(.ciX)` and in plain `Color` positions (`color: .ciX`).

private enum CITheme {
    /// App background: near-black in dark / warm off-white in light.
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.015, green: 0.016, blue: 0.018, alpha: 1)
            : UIColor(red: 0.945, green: 0.925, blue: 0.880, alpha: 1)
    }

    /// Card / capsule surface: pure black in dark / warm white in light (slightly brighter than the background so cards lift off it).
    static let surface = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : UIColor(red: 0.995, green: 0.985, blue: 0.960, alpha: 1)
    }

    /// Primary foreground (base color for text / icons / strokes and light fills): white in dark / warm dark brown in light.
    static let foreground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 1)
            : UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1)
    }
}

extension ShapeStyle where Self == Color {
    static var ciBackground: Color { Color(CITheme.background) }
    static var ciSurface: Color { Color(CITheme.surface) }
    /// Replaces the former `.white` and `.white.opacity(x)`; opacity carries over unchanged.
    static var ciForeground: Color { Color(CITheme.foreground) }
}
