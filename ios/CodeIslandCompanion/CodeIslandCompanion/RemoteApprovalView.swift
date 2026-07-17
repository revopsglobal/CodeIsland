import SwiftUI

struct RemoteApprovalSurface: View {
    @EnvironmentObject private var client: RemoteApprovalClient

    var body: some View {
        Group {
            switch client.state {
            case .unpaired:
                RemotePairingCard()
                    .environmentObject(client)
            case .connecting where client.approvals.isEmpty:
                RemoteApprovalStatusStrip(icon: "lock.iphone", title: "Remote approvals", detail: "Connecting to Mac…", tint: .orange)
            case .offline(let message) where client.approvals.isEmpty:
                RemoteOfflineCard(message: message)
                    .environmentObject(client)
            default:
                if client.approvals.isEmpty {
                    RemoteApprovalStatusStrip(
                        icon: "checkmark.shield.fill",
                        title: "Remote approvals",
                        detail: "Connected · Nothing waiting",
                        tint: .green
                    )
                    .contextMenu {
                        Button("Refresh") { Task { await client.refresh() } }
                        Button("Forget Mac", role: .destructive) { client.unpair() }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(client.approvals) { approval in
                            RemoteApprovalCard(approval: approval)
                                .environmentObject(client)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("companion.remoteApprovals")
    }
}

private struct RemotePairingCard: View {
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Pair remote approvals", systemImage: "lock.iphone")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.ciForeground)

            Text("Use the six-digit code in CodeIsland Settings → Buddy on your Mac.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.ciForeground.opacity(0.56))

            TextField("Tailscale HTTPS URL", text: $client.serverURLText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 11)
                .frame(minHeight: 46)
                .background(Color.ciForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("companion.remote.serverURL")

            TextField("Pairing code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 11)
                .frame(minHeight: 52)
                .background(Color.ciForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: code) { _, value in
                    code = String(value.filter(\.isNumber).prefix(6))
                }
                .accessibilityIdentifier("companion.remote.pairingCode")

            Button {
                Task { await client.pair(code: code) }
            } label: {
                Label("Pair securely", systemImage: "link.badge.plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(Color(red: 0.3, green: 0.85, blue: 0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(code.count != 6 || client.state == .connecting)
            .accessibilityIdentifier("companion.remote.pair")

            if case .offline(let message) = client.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
    }
}

private struct RemoteOfflineCard: View {
    let message: String
    @EnvironmentObject private var client: RemoteApprovalClient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteApprovalStatusStrip(
                icon: "wifi.exclamationmark",
                title: "Remote Mac unavailable",
                detail: message,
                tint: .orange
            )
            HStack(spacing: 8) {
                Button("Retry") { Task { await client.refresh() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.3, green: 0.85, blue: 0.4))
                Button("Pair again", role: .destructive) { client.unpair() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct RemoteApprovalStatusStrip: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.ciForeground.opacity(0.9))
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.ciForeground.opacity(0.48))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.ciSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.ciForeground.opacity(0.07)))
    }
}

private struct RemoteApprovalCard: View {
    let approval: RemoteApprovalItem
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var selection: DecisionSelection?

    private struct DecisionSelection: Identifiable {
        let id = UUID()
        let decision: RemoteApprovalDecision
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(approval.source.uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.orange)
                Spacer()
                Text(approval.createdAt, style: .relative)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.ciForeground.opacity(0.42))
            }

            Text(approval.tool)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.ciForeground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                if let workspace = approval.workspace {
                    remoteChip(icon: "folder", text: workspace)
                }
                remoteChip(icon: "number", text: String(approval.sessionId.suffix(8)))
            }

            if let detail = approval.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.ciForeground.opacity(0.74))
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
            }

            HStack(spacing: 8) {
                remoteAction("Deny", icon: "xmark", tint: .red, decision: .deny)
                remoteAction("Approve once", icon: "checkmark", tint: Color(red: 0.3, green: 0.85, blue: 0.4), decision: .approve)
            }
        }
        .padding(14)
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(
            IslandShellShape().stroke(
                client.highlightedApprovalID == approval.id ? Color.orange : Color.orange.opacity(0.46),
                lineWidth: client.highlightedApprovalID == approval.id ? 2 : 1
            )
        )
        .confirmationDialog(
            selection?.decision == .approve ? "Approve this exact request?" : "Deny this exact request?",
            isPresented: Binding(
                get: { selection != nil },
                set: { if !$0 { selection = nil } }
            ),
            presenting: selection
        ) { selected in
            Button(selected.decision == .approve ? "Approve once" : "Deny", role: selected.decision == .deny ? .destructive : nil) {
                let decision = selected.decision
                selection = nil
                Task { await client.resolve(approval, decision: decision) }
            }
            Button("Cancel", role: .cancel) { selection = nil }
        } message: { _ in
            Text("CodeIsland will re-check the request ID and single-use token on your Mac before executing this decision.")
        }
        .accessibilityIdentifier("companion.remote.approval.\(approval.id)")
    }

    private func remoteChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.ciForeground.opacity(0.55))
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.ciForeground.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
    }

    private func remoteAction(
        _ title: String,
        icon: String,
        tint: Color,
        decision: RemoteApprovalDecision
    ) -> some View {
        Button {
            selection = DecisionSelection(decision: decision)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(decision == .approve ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(tint.opacity(decision == .approve ? 1 : 0.34), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .disabled(client.busyRequestIDs.contains(approval.id))
        .accessibilityIdentifier("companion.remote.\(decision.rawValue).\(approval.id)")
    }
}

