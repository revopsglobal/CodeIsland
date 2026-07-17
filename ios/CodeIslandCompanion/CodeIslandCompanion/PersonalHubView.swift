import SwiftUI
import UIKit

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
                HStack(spacing: 7) {
                    TextField(module.id == .notes ? "New note" : "New task", text: $composerText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.ciForeground)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 38)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("hub.\(module.id.rawValue).composer")
                    Button("Review") {
                        let value = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        Task {
                            await client.prepareHubAction(.init(
                                moduleID: module.id,
                                actionID: "add",
                                value: value
                            ))
                        }
                    }
                    .buttonStyle(HubPrimaryButtonStyle())
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                            if [.reminders, .notes].contains(module.id), action.id == "add" {
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
}

private struct PersonalHubItemRow: View {
    let moduleID: PersonalHubModuleID
    let item: PersonalHubItem
    @EnvironmentObject private var client: RemoteApprovalClient
    @Environment(\.openURL) private var openURL

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
                            if action.id == "copyToDevice", let value = item.detail {
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
