import SwiftUI
import UIKit
import AVFoundation
import Speech
import UniformTypeIdentifiers

enum HubTheme {
    static let accent = Color.orange
    static let foreground = Color.ciForeground
    static let surface = Color.ciSurface
    static let border = Color.ciForeground.opacity(0.08)
    static let iconForeground = Color.ciForeground.opacity(0.68)
    static let iconBackground = Color.ciForeground.opacity(0.045)
}

typealias BuddyQuickJotDestination = PersonalHubQuickJotDestination

extension PersonalHubQuickJotDestination: Identifiable {
    public var id: String { rawValue }
    var title: String { self == .task ? "Task" : "Note" }
    var symbol: String { self == .task ? "checklist" : "note.text" }
}

/// A focused, authenticated session board for the primary Sessions tab.
/// It deliberately fetches the Code rack independently from the selected
/// Home/Work/Code tool mode so Tailscale sessions never degrade into nearby
/// Bluetooth discovery copy.
struct PersonalHubSessionsSurface: View {
    @EnvironmentObject private var client: RemoteApprovalClient

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(HubTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(HubTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Sessions")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(HubTheme.foreground)
                    Text(client.sessionsModule?.summary ?? client.connectionDetail)
                        .font(.subheadline)
                        .foregroundStyle(HubTheme.foreground.opacity(0.52))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(client.state == .connected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(client.state.label)
            }

            if let module = client.sessionsModule {
                if module.items.isEmpty {
                    Label("No active sessions", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(HubTheme.foreground.opacity(0.68))
                        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(module.items) { item in
                            PersonalHubItemRow(moduleID: .agents, item: item)
                            if item.id != module.items.last?.id {
                                Divider().overlay(HubTheme.foreground.opacity(0.07))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .background(HubTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Button {
                    Task { await client.refreshSessions() }
                } label: {
                    Label("Refresh sessions", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(HubSecondaryButtonStyle())
                .accessibilityIdentifier("companion.remote.sessions.refresh")
            } else if let error = client.sessionsError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(HubTheme.accent)
                    Text("Loading sessions from your Mac")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(HubTheme.foreground.opacity(0.66))
                }
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            }
        }
        .padding(20)
        .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(HubTheme.border, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.06), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.remote.sessions")
        .task {
            while !Task.isCancelled {
                await client.refreshSessions()
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    break
                }
            }
        }
    }
}

/// Compact navigation root for the complete personal tool catalog. The former
/// surface rendered every full module in one feed, making equal-weight cards
/// compete with each other. This directory keeps the rack scannable and opens
/// one existing module renderer at a time without changing its action safety.
struct PersonalHubDirectorySurface: View {
    let dismiss: () -> Void

    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var path = NavigationPath()
    @State private var showingRackEditor = false
    @State private var pendingRack: (PersonalHubMode, [PersonalHubModuleID])?
    @State private var pendingQuickJot: (BuddyQuickJotDestination, String)?
    @State private var openedHighlightID: PersonalHubModuleID?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Companion-first collapses the Home/Work/Code racks into one
                    // Companion rack, so the workspace picker is hidden (it would
                    // choose between racks that no longer differ on this phone).
                    if !CompanionFirst.isEnabled {
                        modePicker
                    }

                    if let snapshot = client.hubSnapshot {
                        contextHeader(snapshot)
                        moduleDirectory(snapshot)
                    } else if client.state == .unpaired {
                        emptyState(
                            symbol: "iphone.and.arrow.forward",
                            title: "Connect your Mac",
                            detail: "Pair once to use your private tools from iPhone."
                        )
                    } else if let error = client.hubError {
                        emptyState(
                            symbol: "wifi.exclamationmark",
                            title: "Tools unavailable",
                            detail: error,
                            showsRetry: true
                        )
                    } else {
                        emptyState(
                            symbol: "arrow.triangle.2.circlepath",
                            title: "Loading tools",
                            detail: "Fetching the selected workspace from your Mac."
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .accessibilityIdentifier("hub.surface")
            .background(Color.ciBackground.ignoresSafeArea())
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if client.hubSnapshot?.configuration != nil {
                        Button("Edit") { showingRackEditor = true }
                            .accessibilityIdentifier("hub.rack.edit")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
            .navigationDestination(for: PersonalHubModuleID.self) { moduleID in
                moduleDestination(moduleID)
            }
            .refreshable { await client.refreshHub() }
        }
        .task {
            await client.refreshHub()
            openHighlightedModuleIfNeeded()
        }
        .onChange(of: client.highlightedHubModuleID) { _, _ in
            openHighlightedModuleIfNeeded()
        }
        .onChange(of: client.hubSnapshot?.generatedAt) { _, _ in
            openHighlightedModuleIfNeeded()
        }
        .sheet(item: $client.preparedAction) { prepared in
            PersonalHubConfirmationSheet(prepared: prepared)
                .environmentObject(client)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRackEditor, onDismiss: preparePendingRack) {
            if let snapshot = client.hubSnapshot,
               let configuration = snapshot.configuration {
                PersonalHubModeRackEditor(
                    mode: snapshot.resolvedMode,
                    modules: configuration.rack(for: snapshot.resolvedMode)
                ) { modules in
                    pendingRack = (snapshot.resolvedMode, modules)
                    showingRackEditor = false
                }
            }
        }
        .sheet(item: $client.quickJotDestination, onDismiss: {
            preparePendingQuickJot()
            client.clearQuickJotSeed()
        }) { destination in
            BuddyQuickJotSheet(
                destination: destination,
                initialText: client.quickJotSeedText ?? ""
            ) { text in
                pendingQuickJot = (destination, text)
                client.quickJotDestination = nil
            }
        }
    }

    private var modePicker: some View {
        Picker("Workspace", selection: $client.selectedMode) {
            ForEach(PersonalHubMode.allCases) { mode in
                Text(mode.displayTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("hub.mode.picker")
    }

    private func contextHeader(_ snapshot: PersonalHubSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(snapshot.resolvedMode.displayTitle) tools")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(HubTheme.foreground)
                Text(client.serverName ?? snapshot.serverName)
                    .font(.subheadline)
                    .foregroundStyle(HubTheme.foreground.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Label(client.state == .connected ? "Connected" : client.state.label,
                  systemImage: client.state == .connected ? "checkmark.circle.fill" : "wifi.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(client.state == .connected ? Color.green : Color.orange)
                .labelStyle(.titleAndIcon)
        }
    }

    private func moduleDirectory(_ snapshot: PersonalHubSnapshot) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(snapshot.modules.enumerated()), id: \.element.id) { index, module in
                Button {
                    path.append(module.id)
                } label: {
                    moduleRow(module)
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    client.highlightedHubModuleID == module.id ? "Opened from link" : ""
                )
                .accessibilityIdentifier("hub.module.\(module.id.rawValue)")

                if index < snapshot.modules.count - 1 {
                    Divider()
                        .padding(.leading, 62)
                        .overlay(HubTheme.foreground.opacity(0.07))
                }
            }
        }
        .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HubTheme.border, lineWidth: 0.5)
        )
    }

    private func moduleRow(_ module: PersonalHubModuleSnapshot) -> some View {
        let definition = PersonalHubCatalog.definition(for: module.id)
        return HStack(spacing: 14) {
            Image(systemName: definition.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubTheme.iconForeground)
                .frame(width: 38, height: 38)
                .background(HubTheme.iconBackground, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(HubTheme.foreground)
                Text(module.summary)
                    .font(.subheadline)
                    .foregroundStyle(HubTheme.foreground.opacity(0.48))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            availabilitySymbol(module.availability)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HubTheme.foreground.opacity(0.24))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func availabilitySymbol(_ availability: PersonalHubAvailability) -> some View {
        switch availability {
        case .ready:
            EmptyView()
        case .partial:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(Color.orange)
                .accessibilityLabel("Partially available")
        case .loading:
            ProgressView().controlSize(.small)
        case .permissionRequired:
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(Color.orange)
                .accessibilityLabel("Permission required")
        case .offline:
            Image(systemName: "wifi.slash")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Offline")
        case .unavailable:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Unavailable")
        }
    }

    @ViewBuilder
    private func moduleDestination(_ moduleID: PersonalHubModuleID) -> some View {
        ScrollView {
            if let module = client.hubSnapshot?.modules.first(where: { $0.id == moduleID }) {
                PersonalHubModuleCard(
                    module: module,
                    isHighlighted: client.highlightedHubModuleID == moduleID
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                emptyState(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Loading module",
                    detail: "Refreshing \(PersonalHubCatalog.definition(for: moduleID).title)."
                )
                .padding(20)
            }
        }
        .background(Color.ciBackground.ignoresSafeArea())
        .navigationTitle(PersonalHubCatalog.definition(for: moduleID).title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func emptyState(
        symbol: String,
        title: String,
        detail: String,
        showsRetry: Bool = false
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(HubTheme.accent)
            Text(title)
                .font(.headline)
                .foregroundStyle(HubTheme.foreground)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(HubTheme.foreground.opacity(0.5))
                .multilineTextAlignment(.center)
            if showsRetry {
                Button("Retry") { Task { await client.refreshHub() } }
                    .buttonStyle(.borderedProminent)
                    .tint(HubTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func openHighlightedModuleIfNeeded() {
        guard let moduleID = client.highlightedHubModuleID,
              moduleID != openedHighlightID,
              client.hubSnapshot?.modules.contains(where: { $0.id == moduleID }) == true
        else { return }
        openedHighlightID = moduleID
        path = NavigationPath()
        path.append(moduleID)
    }

    private func preparePendingRack() {
        guard let (mode, modules) = pendingRack else { return }
        pendingRack = nil
        let mutation = PersonalHubConfigurationMutation(mode: mode, modules: modules)
        Task {
            await client.prepareHubAction(.init(
                moduleID: .quickToggles,
                actionID: "setModeRack",
                value: mutation.encodedActionValue()
            ))
        }
    }

    private func preparePendingQuickJot() {
        guard let (destination, text) = pendingQuickJot else { return }
        pendingQuickJot = nil
        let intent: PersonalHubActionIntent
        switch destination {
        case .task:
            intent = .init(
                moduleID: .reminders,
                actionID: "add",
                value: PersonalHubReminderDraft(title: text).encodedActionValue()
            )
        case .note:
            intent = .init(moduleID: .notes, actionID: "add", value: text)
        }
        Task { await client.prepareHubAction(intent) }
    }
}

struct PersonalHubSurface: View {
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var showingRackEditor = false
    @State private var pendingRack: (PersonalHubMode, [PersonalHubModuleID])?
    @State private var pendingQuickJot: (BuddyQuickJotDestination, String)?

    var body: some View {
        VStack(spacing: 14) {
            modeStrip
            connectionStrip
            quickJotStrip

            if let snapshot = client.hubSnapshot {
                HStack(spacing: 8) {
                    Text("\(snapshot.resolvedMode.displayTitle) tools")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HubTheme.accent)
                    Spacer(minLength: 0)
                    Text("Updated \(snapshot.generatedAt, style: .time)")
                        .font(.caption)
                        .foregroundStyle(HubTheme.foreground.opacity(0.42))
                    Button {
                        toggleDashboard(snapshot)
                    } label: {
                        Image(systemName: snapshot.configuration?.dashboardEnabled == false
                            ? "gauge.with.dots.needle.0percent"
                            : "gauge.with.dots.needle.67percent")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubTheme.foreground.opacity(0.52))
                    .accessibilityLabel(snapshot.configuration?.dashboardEnabled == false
                        ? "Show day dashboard"
                        : "Hide day dashboard")
                    .accessibilityIdentifier("hub.dashboard.toggle")
                    Button {
                        showingRackEditor = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubTheme.accent)
                    .accessibilityLabel("Edit \(snapshot.resolvedMode.displayTitle) rack")
                    .accessibilityIdentifier("hub.rack.edit")
                }
                .padding(.horizontal, 4)

                if snapshot.configuration?.dashboardEnabled != false,
                   let dayProgress = snapshot.dayProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("DAY")
                            Spacer()
                            Text("\(Int((dayProgress * 100).rounded()))%")
                        }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(HubTheme.foreground.opacity(0.42))
                        ProgressView(value: dayProgress)
                            .tint(HubTheme.accent)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("hub.dayProgress")
                }

                LazyVStack(spacing: 9) {
                    ForEach(snapshot.modules) { module in
                        PersonalHubModuleCard(
                            module: module,
                            isHighlighted: client.highlightedHubModuleID == module.id
                        )
                    }
                }
            } else if client.state == .unpaired {
                hubEmptyState(
                    symbol: "iphone.and.arrow.forward",
                    title: "Pair with your Mac",
                    detail: "Use the six-digit code in Code Island Settings → Buddy."
                )
            } else if let error = client.hubError {
                hubEmptyState(
                    symbol: "wifi.exclamationmark",
                    title: "Tools unavailable",
                    detail: error,
                    showsRetry: true
                )
            } else {
                hubEmptyState(
                    symbol: "arrow.triangle.2.circlepath",
                    title: "Loading your Mac",
                    detail: "Fetching the selected workspace from your Mac."
                )
            }

        }
        .padding(.horizontal, 2)
        .padding(.bottom, 12)
        .task { await client.refreshHub() }
        .sheet(item: $client.preparedAction) { prepared in
            PersonalHubConfirmationSheet(prepared: prepared)
                .environmentObject(client)
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRackEditor, onDismiss: preparePendingRack) {
            if let snapshot = client.hubSnapshot,
               let configuration = snapshot.configuration {
                PersonalHubModeRackEditor(
                    mode: snapshot.resolvedMode,
                    modules: configuration.rack(for: snapshot.resolvedMode)
                ) { modules in
                    pendingRack = (snapshot.resolvedMode, modules)
                    showingRackEditor = false
                }
            }
        }
        .sheet(item: $client.quickJotDestination, onDismiss: {
            preparePendingQuickJot()
            client.clearQuickJotSeed()
        }) { destination in
            BuddyQuickJotSheet(destination: destination, initialText: client.quickJotSeedText ?? "") { text in
                pendingQuickJot = (destination, text)
                client.quickJotDestination = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.surface")
    }

    private var quickJotStrip: some View {
        HStack(spacing: 7) {
            ForEach(BuddyQuickJotDestination.allCases) { destination in
                Button {
                    client.quickJotDestination = destination
                } label: {
                    Label("New \(destination.title)", systemImage: destination.symbol)
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(HubSecondaryButtonStyle())
                .accessibilityIdentifier("hub.quickJot.\(destination.rawValue)")
            }
        }
    }

    private var connectionStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(client.state == .connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(client.state.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(client.state == .connected ? Color.green : Color.orange)
                Text(client.serverName ?? "Your paired Mac")
                    .font(.caption)
                    .foregroundStyle(HubTheme.foreground.opacity(0.42))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if case .offline = client.state {
                Button("Retry") { Task { await client.refresh() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(HubTheme.accent)
                    .accessibilityIdentifier("hub.connection.retry")
            }
        }
        .padding(.horizontal, 4)
        .accessibilityIdentifier("hub.connection.status")
    }

    private func toggleDashboard(_ snapshot: PersonalHubSnapshot) {
        let mutation = PersonalHubConfigurationMutation(
            dashboardEnabled: !(snapshot.configuration?.dashboardEnabled ?? true)
        )
        Task {
            await client.prepareHubAction(.init(
                moduleID: .quickToggles,
                actionID: "setDashboard",
                value: mutation.encodedActionValue()
            ))
        }
    }

    private func preparePendingRack() {
        guard let (mode, modules) = pendingRack else { return }
        pendingRack = nil
        let mutation = PersonalHubConfigurationMutation(mode: mode, modules: modules)
        Task {
            await client.prepareHubAction(.init(
                moduleID: .quickToggles,
                actionID: "setModeRack",
                value: mutation.encodedActionValue()
            ))
        }
    }

    private func preparePendingQuickJot() {
        guard let (destination, text) = pendingQuickJot else { return }
        pendingQuickJot = nil
        let intent: PersonalHubActionIntent
        switch destination {
        case .task:
            intent = .init(
                moduleID: .reminders,
                actionID: "add",
                value: PersonalHubReminderDraft(title: text).encodedActionValue()
            )
        case .note:
            intent = .init(moduleID: .notes, actionID: "add", value: text)
        }
        Task { await client.prepareHubAction(intent) }
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            client.selectedMode == mode ? Color.black : HubTheme.foreground.opacity(0.58)
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            client.selectedMode == mode ? HubTheme.accent : HubTheme.surface,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hub.mode.\(mode.rawValue)")
            }
        }
    }

    private func hubEmptyState(
        symbol: String,
        title: String,
        detail: String,
        showsRetry: Bool = false
    ) -> some View {
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
            if showsRetry {
                Button("Retry") { Task { await client.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(HubTheme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

private struct BuddyQuickJotSheet: View {
    let destination: BuddyQuickJotDestination
    let initialText: String
    let onReview: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(
        destination: BuddyQuickJotDestination,
        initialText: String = "",
        onReview: @escaping (String) -> Void
    ) {
        self.destination = destination
        self.initialText = initialText
        self.onReview = onReview
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Label("Save to \(destination.title)", systemImage: destination.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(HubTheme.accent)
                TextField(
                    destination == .task ? "What needs doing?" : "What do you want to remember?",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .padding(12)
                .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .focused($focused)
                .accessibilityIdentifier("hub.quickJot.text")
                Spacer()
            }
            .padding(16)
            .background(Color.black)
            .navigationTitle("New \(destination.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        onReview(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { focused = true }
        .accessibilityIdentifier("hub.quickJot.sheet")
    }
}

private struct PersonalHubModeRackEditor: View {
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
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    Text("PINNED")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(Array(modules.enumerated()), id: \.element) { index, module in
                        moduleRow(module) {
                            HStack(spacing: 14) {
                                Button { move(index, by: -1) } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .disabled(index == 0)
                                .accessibilityLabel("Move \(PersonalHubCatalog.definition(for: module).title) up")
                                .accessibilityIdentifier("hub.rack.moveUp.\(module.rawValue)")
                                Button { move(index, by: 1) } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .disabled(index == modules.count - 1)
                                .accessibilityLabel("Move \(PersonalHubCatalog.definition(for: module).title) down")
                                .accessibilityIdentifier("hub.rack.moveDown.\(module.rawValue)")
                                Button { modules.remove(at: index) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .disabled(modules.count == 1)
                                .accessibilityLabel("Remove \(PersonalHubCatalog.definition(for: module).title)")
                                .accessibilityIdentifier("hub.rack.remove.\(module.rawValue)")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(HubTheme.accent)
                        }
                    }

                    if !availableModules.isEmpty {
                        Text("AVAILABLE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)

                        ForEach(availableModules) { module in
                            moduleRow(module) {
                                Button { modules.append(module) } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(HubTheme.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.black)
            .navigationTitle("\(mode.displayTitle) rack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") { onSave(modules) }
                        .disabled(modules.isEmpty)
                        .accessibilityIdentifier("hub.rack.review")
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("hub.rack.editor")
    }

    private func moduleRow<Trailing: View>(
        _ module: PersonalHubModuleID,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: PersonalHubCatalog.definition(for: module).symbol)
                .foregroundStyle(HubTheme.accent)
                .frame(width: 24)
            Text(PersonalHubCatalog.definition(for: module).title)
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            trailing()
        }
        .padding(12)
        .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(HubTheme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("hub.rack.module.\(module.rawValue)")
    }

    private var availableModules: [PersonalHubModuleID] {
        // Under companion-first, only keeper modules can be added back, so the
        // editor cannot re-expose a trimmed module (closes the catalog leak).
        CompanionFirst.filteredCatalog(PersonalHubModuleID.allCases).filter { !modules.contains($0) }
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard modules.indices.contains(index), modules.indices.contains(destination) else { return }
        modules.swapAt(index, destination)
    }
}

private struct PersonalHubModuleCard: View {
    let module: PersonalHubModuleSnapshot
    let isHighlighted: Bool
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var claudeContexts: [PersonalHubClaudeContext] = []
    @State private var claudeContextError: String?
    @State private var showsClaudeFileImporter = false
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
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: module.id == .notifications ? "eye.slash" : "info.circle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(module.id == .notifications ? HubTheme.accent : HubTheme.foreground.opacity(0.38))
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(HubTheme.foreground.opacity(0.44))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(HubTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if showsComposer {
                composer
            }

            if let month = module.calendarMonth {
                BuddyCalendarMonthView(month: month)

                VStack(alignment: .leading, spacing: 5) {
                    Text(month.selectedEvents.isEmpty ? "NO EVENTS" : "SELECTED DAY")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(HubTheme.foreground.opacity(0.32))
                    if !month.selectedEvents.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(month.selectedEvents) { item in
                                PersonalHubItemRow(moduleID: module.id, item: item)
                                if item.id != month.selectedEvents.last?.id {
                                    Divider().overlay(HubTheme.foreground.opacity(0.07))
                                }
                            }
                        }
                        .background(HubTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("hub.calendar.selectedEvents")
            }

            if !module.items.isEmpty {
                if module.calendarMonth != nil {
                    Text("UPCOMING")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(HubTheme.foreground.opacity(0.32))
                }
                LazyVStack(spacing: 0) {
                    ForEach(module.calendarMonth == nil ? module.items : Array(module.items.prefix(6))) { item in
                        PersonalHubItemRow(moduleID: module.id, item: item)
                        if item.id != (module.calendarMonth == nil ? module.items.last?.id : module.items.prefix(6).last?.id) {
                            Divider().overlay(HubTheme.foreground.opacity(0.07))
                        }
                    }
                }
                .background(HubTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            } else if handleReadOnly(action) {
                                return
                            } else {
                                prepare(action)
                            }
                        } label: {
                            Label(action.label, systemImage: action.symbol ?? "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(HubSecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .background(HubTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHighlighted ? HubTheme.accent : HubTheme.border, lineWidth: isHighlighted ? 1.5 : 0.5)
        )
        .shadow(color: Color.black.opacity(0.045), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.module.\(module.id.rawValue)")
        .accessibilityValue(isHighlighted ? "Opened from link" : "")
        .fullScreenCover(isPresented: $showsCameraPreview) {
            MediaPreflightView()
        }
        .fileImporter(
            isPresented: $showsClaudeFileImporter,
            allowedContentTypes: [.plainText, .json, .commaSeparatedText, .sourceCode, .data],
            allowsMultipleSelection: true,
            onCompletion: importClaudeFiles
        )
        .onAppear {
            if selectedReminderCalendarID.isEmpty {
                selectedReminderCalendarID = reminderLists.first?.id ?? ""
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { speech.cancel() }
        }
        .onDisappear { speech.cancel() }
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
        if module.id == .camera, action.id == "previewLocal" {
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

    private func handleReadOnly(_ action: PersonalHubAction) -> Bool {
        guard PersonalHubBuddyParity.isReadOnlyAction(moduleID: module.id, actionID: action.id) else {
            return false
        }
        if action.id == "refresh" {
            Task {
                await client.refreshHub()
                client.reportHubClientAction("Refreshed \(definition.title)")
            }
        } else {
            client.reportHubClientAction("\(definition.title) updated")
        }
        return true
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
                    .background(HubTheme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    hubTextField(composerActionID == "plan" ? "Tell Claude what to propose" : "Ask Claude", text: $composerText)
                    reviewButton(
                        actionID: composerActionID,
                        value: PersonalHubClaudeDraft(
                            prompt: composerText.trimmingCharacters(in: .whitespacesAndNewlines),
                            contexts: claudeContexts
                        ).encodedActionValue()
                    )
                }

                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(HubSpeechRecognizer.Mode.allCases) { mode in
                            Button {
                                speech.setMode(mode)
                            } label: {
                                Text(mode == .pushToTalk ? "HOLD" : "CONTINUOUS")
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundStyle(speech.mode == mode ? Color.black : HubTheme.foreground.opacity(0.5))
                                    .frame(minWidth: mode == .pushToTalk ? 72 : 96, minHeight: 44)
                                    .background(
                                        speech.mode == mode ? HubTheme.accent : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("hub.claude.voice.\(mode.rawValue)")
                        }
                    }
                    .padding(3)
                    .background(HubTheme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Spacer(minLength: 0)

                    if speech.mode == .pushToTalk {
                        Label(speech.isRecording ? "Listening" : "Hold to talk", systemImage: speech.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(speech.isRecording ? HubTheme.accent : HubTheme.foreground.opacity(0.7))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(HubTheme.foreground.opacity(0.055), in: Capsule())
                            .contentShape(Capsule())
                            .onLongPressGesture(
                                minimumDuration: 0,
                                maximumDistance: 32,
                                pressing: { pressing in
                                    if pressing {
                                        speech.press { composerText = $0 }
                                    } else {
                                        speech.release()
                                    }
                                },
                                perform: {}
                            )
                            .accessibilityLabel("Hold to dictate a Claude request")
                            .accessibilityIdentifier("hub.claude.voice.hold")
                    } else {
                        Button {
                            speech.toggle { composerText = $0 }
                        } label: {
                            Label(speech.isRecording ? "Stop" : "Listen", systemImage: speech.isRecording ? "stop.fill" : "waveform")
                                .font(.system(size: 10, weight: .bold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(HubPrimaryButtonStyle())
                    }
                }

                if speech.phase == .requestingPermission {
                    Label("Requesting private microphone access…", systemImage: "lock.shield")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HubTheme.foreground.opacity(0.48))
                } else if let error = speech.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubTheme.accent)
                }

                if !claudeContexts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(claudeContexts.enumerated()), id: \.offset) { index, context in
                                HStack(spacing: 5) {
                                    Image(systemName: "doc.text")
                                    Text(context.name).lineLimit(1)
                                    Button {
                                        claudeContexts.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(context.name)")
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(context.wasTruncated ? HubTheme.accent : HubTheme.foreground.opacity(0.7))
                                .padding(.leading, 9)
                                .frame(minHeight: 44)
                                .background(HubTheme.foreground.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 7) {
                    Button {
                        showsClaudeFileImporter = true
                    } label: {
                        Label("Attach text", systemImage: "paperclip")
                            .font(.system(size: 10, weight: .bold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(HubSecondaryButtonStyle())
                    .accessibilityIdentifier("hub.claude.attach")
                    Text("5 files max · 2 MB each")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(HubTheme.foreground.opacity(0.34))
                }

                if let claudeContextError {
                    Text(claudeContextError)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubTheme.accent)
                }

                Text("Voice and attached text are sent privately to your paired Mac. Ask is read-only; Do only creates proposals you must review again.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(HubTheme.foreground.opacity(0.36))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hub.claude.safety")
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
            .frame(minHeight: 44)
            .background(HubTheme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .accessibilityIdentifier("hub.\(module.id.rawValue).review")
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

    private func importClaudeFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            let namedData = try urls.map { url -> (String, Data) in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return (url.lastPathComponent, try Data(contentsOf: url, options: [.mappedIfSafe]))
            }
            claudeContexts = try PersonalHubClaudeContextPolicy.validate(namedData: namedData)
            claudeContextError = nil
        } catch {
            claudeContextError = error.localizedDescription
        }
    }
}

private struct BuddyCalendarMonthView: View {
    let month: PersonalHubCalendarMonth

    @EnvironmentObject private var client: RemoteApprovalClient
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            monthHeader
            monthGrid
        }
        .padding(9)
        .background(HubTheme.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HubTheme.border, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.calendar.month")
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            navigationButton("chevron.left", label: "Previous month", identifier: "previous") {
                moveMonth(-1)
            }
            Spacer(minLength: 0)
            monthTitle
            Spacer(minLength: 0)
            todayButton
            navigationButton("chevron.right", label: "Next month", identifier: "next") {
                moveMonth(1)
            }
        }
    }

    private var monthTitle: some View {
        Text(month.displayedMonth.formatted(.dateTime.month(.wide).year()))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(HubTheme.foreground.opacity(0.9))
            .accessibilityIdentifier("hub.calendar.monthTitle")
    }

    private var todayButton: some View {
        Button("Today") {
            Task { await client.refreshCalendar(referenceDate: Date(), selectedDate: Date()) }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(HubTheme.accent)
        .buttonStyle(.plain)
        .accessibilityIdentifier("hub.calendar.today")
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                weekdayLabel(symbol)
            }
            ForEach(month.days) { day in
                dayButton(day)
            }
        }
    }

    private func weekdayLabel(_ symbol: String) -> some View {
        Text(symbol.uppercased())
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(HubTheme.foreground.opacity(0.28))
            .frame(maxWidth: .infinity)
    }

    private func dayButton(_ day: PersonalHubCalendarDay) -> some View {
        Button {
            select(day)
        } label: {
            dayLabel(day)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hub.calendar.day.\(day.id)")
        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(eventCountLabel(day.eventCount))
    }

    private func dayLabel(_ day: PersonalHubCalendarDay) -> some View {
        let selected = isSelected(day)
        let foreground = day.isInDisplayedMonth
            ? HubTheme.foreground.opacity(0.86)
            : HubTheme.foreground.opacity(0.22)
        let fill = selected ? HubTheme.accent.opacity(0.24) : Color.clear
        let stroke = day.isToday ? HubTheme.accent.opacity(0.92) : Color.clear

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: day.date))")
                .font(.system(size: 11, weight: selected ? .bold : .medium, design: .rounded))
            eventDots(day.eventCount)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(stroke, lineWidth: 1)
        )
    }

    private func eventDots(_ count: Int) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle().frame(width: 2.5, height: 2.5)
            }
        }
        .frame(height: 3)
    }

    private func select(_ day: PersonalHubCalendarDay) {
        Task {
            await client.refreshCalendar(
                referenceDate: month.displayedMonth,
                selectedDate: day.date
            )
        }
    }

    private func eventCountLabel(_ count: Int) -> String {
        count == 1 ? "1 event" : "\(count) events"
    }

    private func navigationButton(
        _ symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.055), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(HubTheme.accent)
        .accessibilityLabel(label)
        .accessibilityIdentifier("hub.calendar.\(identifier)")
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
        Task { await client.refreshCalendar(referenceDate: reference, selectedDate: reference) }
    }
}

@MainActor
private final class HubSpeechRecognizer: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case pushToTalk
        case continuous
        var id: String { rawValue }
    }

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case listening
        case blocked
    }

    @Published private(set) var isRecording = false
    @Published private(set) var mode: Mode = .pushToTalk
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var tapInstalled = false
    private let sessionQueue = DispatchQueue(label: "com.codeisland.buddy.speech-session")
    private var startGeneration = UUID()

    func setMode(_ mode: Mode) {
        startGeneration = UUID()
        if isRecording { stop() }
        self.mode = mode
        errorMessage = nil
    }

    func press(onTranscript: @escaping (String) -> Void) {
        guard mode == .pushToTalk, !isRecording else { return }
        beginStart(onTranscript: onTranscript)
    }

    func release() {
        guard mode == .pushToTalk else { return }
        startGeneration = UUID()
        if isRecording {
            stop()
        } else if phase == .requestingPermission {
            phase = .idle
        }
    }

    func toggle(onTranscript: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            beginStart(onTranscript: onTranscript)
        }
    }

    private func beginStart(onTranscript: @escaping (String) -> Void) {
        let generation = UUID()
        startGeneration = generation
        Task { await start(generation: generation, onTranscript: onTranscript) }
    }

    private func start(generation: UUID, onTranscript: @escaping (String) -> Void) async {
        phase = .requestingPermission
        errorMessage = nil
        let speechAuthorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard startGeneration == generation else { return }
        guard speechAuthorization == .authorized, microphoneAllowed else {
            phase = .blocked
            errorMessage = "Enable Speech Recognition and Microphone in Settings"
            return
        }
        guard recognizer?.isAvailable == true else {
            phase = .blocked
            errorMessage = "Speech Recognition is currently unavailable"
            return
        }

        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition == true
        self.request = request

        do {
            try await activateAudioSession()
            let node = audioEngine.inputNode
            let format = node.outputFormat(forBus: 0)
            node.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            phase = .listening
            scheduleSilenceTimeout()
            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result {
                        onTranscript(result.bestTranscription.formattedString)
                        self?.scheduleSilenceTimeout()
                    }
                    if result?.isFinal == true || error != nil {
                        self?.stop()
                    }
                }
            }
        } catch {
            stop()
            phase = .blocked
            errorMessage = "Microphone could not start: \(error.localizedDescription)"
        }
    }

    private func scheduleSilenceTimeout() {
        silenceTask?.cancel()
        guard mode == .continuous else { return }
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        silenceTask?.cancel()
        silenceTask = nil
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
        if phase != .blocked { phase = .idle }
        deactivateAudioSession()
    }

    func cancel() {
        startGeneration = UUID()
        stop()
        errorMessage = nil
        phase = .idle
    }

    private func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deactivateAudioSession() {
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
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
    @State private var mediaSeekPosition = 0.0
    @State private var isMediaSeeking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let data = item.decodedArtworkJPEG, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(HubTheme.border, lineWidth: 1)
                        )
                } else if let symbol = item.symbol {
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

            if moduleID == .claude,
               let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(HubTheme.foreground.opacity(0.78))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("hub.item.detail.\(moduleID.rawValue).\(item.id)")
            }

            if let progress = item.progress {
                ProgressView(value: progress).tint(HubTheme.accent)
            }

            if let duration = item.mediaDuration, duration.isFinite, duration > 0 {
                Slider(
                    value: $mediaSeekPosition,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        isMediaSeeking = editing
                        guard !editing else { return }
                        Task {
                            await client.prepareHubAction(.init(
                                moduleID: moduleID,
                                actionID: "seek",
                                targetID: item.id,
                                value: String(mediaSeekPosition)
                            ))
                        }
                    }
                )
                .tint(HubTheme.accent)
                .accessibilityLabel("Playback position")
                .accessibilityIdentifier("hub.seek.\(moduleID.rawValue)")
                HStack {
                    Text(playbackTime(mediaSeekPosition))
                    Spacer()
                    Text(playbackTime(duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(HubTheme.foreground.opacity(0.36))
                .onAppear {
                    mediaSeekPosition = min(max(item.mediaPosition ?? 0, 0), duration)
                }
                .onChange(of: item.mediaPosition) { _, position in
                    guard !isMediaSeeking else { return }
                    mediaSeekPosition = min(max(position ?? 0, 0), duration)
                }
            }

            if !item.actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(item.actions) { action in
                            Button {
                            if action.id == "downloadToDevice" {
                                Task {
                                    if let url = await client.downloadHubFile(
                                        moduleID: moduleID,
                                        id: item.id,
                                        filename: item.title
                                    ) {
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
                            } else if handleReadOnly(action) {
                                return
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
                            .accessibilityIdentifier("hub.action.\(moduleID.rawValue).\(action.id)")
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

    private func playbackTime(_ seconds: TimeInterval) -> String {
        let whole = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func handleReadOnly(_ action: PersonalHubAction) -> Bool {
        guard PersonalHubBuddyParity.isReadOnlyAction(moduleID: moduleID, actionID: action.id) else {
            return false
        }
        let title = PersonalHubCatalog.definition(for: moduleID).title
        if action.id == "refresh" {
            Task {
                await client.refreshHub()
                client.reportHubClientAction("Refreshed \(title)")
            }
        } else {
            client.reportHubClientAction("\(title) updated")
        }
        return true
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
            .frame(minHeight: 44)
            .background(HubTheme.accent.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HubSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(HubTheme.foreground.opacity(configuration.isPressed ? 0.55 : 0.74))
            .background(HubTheme.foreground.opacity(configuration.isPressed ? 0.1 : 0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct HubCompactButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color.black : HubTheme.foreground.opacity(0.7))
            .padding(.horizontal, 9)
            .frame(minHeight: 44)
            .background(
                primary ? HubTheme.accent : HubTheme.foreground.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension PersonalHubMode {
    var displayTitle: String {
        switch self {
        case .auto: return "Auto"
        case .home: return "Home"
        case .work: return "Work"
        case .code: return "Code"
        }
    }
}
