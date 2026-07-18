import SwiftUI

struct RemoteApprovalSurface: View {
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var selectedAttentionID: String?

    var body: some View {
        Group {
            switch client.state {
            case .unpaired:
                RemotePairingCard()
                    .environmentObject(client)
            case .connecting where !client.hasPairingCredential:
                RemotePairingCard()
                    .environmentObject(client)
            case .offline where !client.hasPairingCredential:
                RemotePairingCard()
                    .environmentObject(client)
            case .connecting where client.approvals.isEmpty && client.questions.isEmpty:
                RemoteApprovalStatusStrip(icon: "lock.iphone", title: "Remote approvals", detail: "Connecting to Mac…", tint: .orange)
            case .offline(let message) where client.approvals.isEmpty && client.questions.isEmpty:
                RemoteOfflineCard(message: message)
                    .environmentObject(client)
            default:
                if attentionItems.isEmpty {
                    EmptyView()
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if attentionItems.count > 1 {
                            HStack {
                                Text("Attention queue")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.ciForeground.opacity(0.58))
                                Spacer()
                                Menu {
                                    ForEach(attentionItems) { item in
                                        Button {
                                            selectedAttentionID = item.id
                                        } label: {
                                            Label(item.menuTitle, systemImage: item.symbol)
                                        }
                                    }
                                } label: {
                                    Text("\(selectedIndex + 1) of \(attentionItems.count)")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 4)
                        }

                        if let selectedAttention {
                            switch selectedAttention {
                            case .approval(let approval):
                                RemoteApprovalCard(approval: approval)
                                    .environmentObject(client)
                            case .question(let question):
                                RemoteQuestionCard(question: question)
                                    .environmentObject(client)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("companion.attention.stage")
                }
            }
        }
        .accessibilityIdentifier("companion.remoteApprovals")
        .onAppear { synchronizeAttentionSelection() }
        .onChange(of: attentionIDs) { _, _ in synchronizeAttentionSelection() }
    }

    private var attentionItems: [RemoteAttentionCardItem] {
        client.approvals.map(RemoteAttentionCardItem.approval)
            + client.questions.map(RemoteAttentionCardItem.question)
    }

    private var attentionIDs: [String] {
        attentionItems.map(\.id)
    }

    private var selectedAttention: RemoteAttentionCardItem? {
        let resolvedID = CompanionAttentionSelection.resolve(
            previousID: selectedAttentionID,
            currentIDs: attentionIDs
        )
        return attentionItems.first(where: { $0.id == resolvedID })
    }

    private var selectedIndex: Int {
        guard let selectedAttention,
              let index = attentionItems.firstIndex(where: { $0.id == selectedAttention.id })
        else { return 0 }
        return index
    }

    private func synchronizeAttentionSelection() {
        selectedAttentionID = CompanionAttentionSelection.resolve(
            previousID: selectedAttentionID,
            currentIDs: attentionIDs
        )
    }
}

private enum RemoteAttentionCardItem: Identifiable {
    case approval(RemoteApprovalItem)
    case question(RemoteQuestionItem)

    var id: String {
        switch self {
        case .approval(let approval): return approval.id
        case .question(let question): return question.id
        }
    }

    var menuTitle: String {
        switch self {
        case .approval(let approval): return approval.tool
        case .question(let question): return question.prompts.first?.question ?? "Question"
        }
    }

    var symbol: String {
        switch self {
        case .approval: return "checkmark.shield"
        case .question: return "questionmark.bubble"
        }
    }
}

private struct RemoteQuestionCard: View {
    let question: RemoteQuestionItem
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var singleSelections: [String: String] = [:]
    @State private var multiSelections: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]
    @State private var confirming = false

    private var resolvedAnswers: [String] {
        question.prompts.map { prompt in
            let custom = customAnswers[prompt.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if prompt.allowsMultipleSelection {
                var values = Array(multiSelections[prompt.id, default: []]).sorted()
                if !custom.isEmpty { values.append(custom) }
                return values.joined(separator: ", ")
            }
            return custom.isEmpty ? singleSelections[prompt.id, default: ""] : custom
        }
    }

    private var canSubmit: Bool {
        !question.requiresLocalResponse
            && !question.prompts.isEmpty
            && resolvedAnswers.allSatisfy { !$0.isEmpty }
            && !client.busyRequestIDs.contains(question.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label("Decision needed", systemImage: "questionmark.bubble.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)
                Spacer()
                Text(question.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.ciForeground.opacity(0.42))
            }

            HStack(spacing: 6) {
                Text(question.source)
                if let workspace = question.workspace, !workspace.isEmpty {
                    Text("·")
                    Text(workspace)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ciForeground.opacity(0.52))

            if question.requiresLocalResponse {
                Label("Sensitive question waiting on Mac", systemImage: "eye.slash.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("Its text and choices are intentionally never sent to this device.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.ciForeground.opacity(0.62))
            } else {
                ForEach(question.prompts) { prompt in
                    VStack(alignment: .leading, spacing: 12) {
                        if let header = prompt.header, !header.isEmpty {
                            Text(header)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        Text(prompt.question)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.ciForeground)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(prompt.options.indices, id: \.self) { index in
                            let option = prompt.options[index]
                            Button {
                                if prompt.allowsMultipleSelection {
                                    var selected = multiSelections[prompt.id, default: []]
                                    if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
                                    multiSelections[prompt.id] = selected
                                } else {
                                    singleSelections[prompt.id] = option
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: isSelected(option, for: prompt)
                                          ? (prompt.allowsMultipleSelection ? "checkmark.square.fill" : "largecircle.fill.circle")
                                          : (prompt.allowsMultipleSelection ? "square" : "circle"))
                                        .foregroundStyle(isSelected(option, for: prompt) ? Color.blue : Color.ciForeground.opacity(0.38))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option)
                                            .font(.system(size: 13, weight: .bold))
                                        if prompt.descriptions.indices.contains(index) {
                                            Text(prompt.descriptions[index])
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.ciForeground.opacity(0.52))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.ciForeground)
                                .padding(12)
                                .background(
                                    isSelected(option, for: prompt)
                                        ? Color.blue.opacity(0.12)
                                        : Color.ciForeground.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option)
                        }

                        TextField(prompt.options.isEmpty ? "Type your answer" : "Or type a custom answer", text: customBinding(for: prompt.id))
                            .textInputAutocapitalization(.sentences)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 13)
                            .frame(minHeight: 48)
                            .background(Color.ciForeground.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                    }
                }

                Button {
                    confirming = true
                } label: {
                    Label("Send answer", systemImage: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.10), Color.ciSurface],
                startPoint: .topLeading,
                endPoint: .center
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(
                client.highlightedQuestionID == question.id ? Color.blue.opacity(0.70) : Color.blue.opacity(0.16),
                lineWidth: client.highlightedQuestionID == question.id ? 1.5 : 0.5
            )
        )
        .shadow(color: Color.blue.opacity(0.08), radius: 24, y: 12)
        .confirmationDialog(
            "Send this answer to the exact waiting agent request?",
            isPresented: $confirming
        ) {
            Button("Send answer") {
                let answers = resolvedAnswers
                Task { await client.answer(question, answers: answers) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Mac re-checks the question ID and a single-use token before delivering it.")
        }
        .accessibilityIdentifier("companion.remote.question.\(question.id)")
    }

    private func isSelected(_ option: String, for prompt: RemoteQuestionPrompt) -> Bool {
        prompt.allowsMultipleSelection
            ? multiSelections[prompt.id, default: []].contains(option)
            : singleSelections[prompt.id] == option
    }

    private func customBinding(for id: String) -> Binding<String> {
        Binding(
            get: { customAnswers[id, default: ""] },
            set: { customAnswers[id] = $0 }
        )
    }
}

private struct RemotePairingCard: View {
    @EnvironmentObject private var client: RemoteApprovalClient
    @State private var code = ""
    @State private var showsConnectionSettings = false

    private var isConnecting: Bool {
        client.state == .connecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Greg's Mac")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.ciForeground)
                    Text("Private to your Tailscale network")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.ciForeground.opacity(0.5))
                }
            }

            Label("On your Mac: CodeIsland Settings → Buddy", systemImage: "1.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.ciForeground.opacity(0.7))

            Label("Enter the current six-digit code", systemImage: "2.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.ciForeground.opacity(0.7))

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

            DisclosureGroup("Connection settings", isExpanded: $showsConnectionSettings) {
                TextField("Tailscale HTTPS URL", text: $client.serverURLText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 11)
                    .frame(minHeight: 46)
                    .background(Color.ciForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("companion.remote.serverURL")
                    .padding(.top, 8)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.ciForeground.opacity(0.56))
            .accessibilityIdentifier("companion.remote.connectionSettings")

            Button {
                Task {
                    if !(await client.pair(code: code)) {
                        code = ""
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.black)
                    } else {
                        Image(systemName: "lock.open.fill")
                    }
                    Text(isConnecting ? "Connecting…" : "Connect securely")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(red: 0.3, green: 0.85, blue: 0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(code.count != 6 || isConnecting)
            .opacity(code.count == 6 && !isConnecting ? 1 : 0.5)
            .accessibilityIdentifier("companion.remote.pair")

            if case .offline(let message) = client.state {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
        .accessibilityIdentifier("companion.remote.pairingCard")
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label("Approval needed", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Text(approval.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.ciForeground.opacity(0.42))
            }

            HStack(spacing: 6) {
                Text(approval.source)
                if let workspace = approval.workspace, !workspace.isEmpty {
                    Text("·")
                    Text(workspace)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.ciForeground.opacity(0.52))

            Text(approval.tool)
                .font(.title3.weight(.bold))
                .foregroundStyle(.ciForeground)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = approval.detail, !detail.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Requested action", systemImage: "terminal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ciForeground.opacity(0.5))
                    Text(detail)
                        .font(.system(.callout, design: .monospaced, weight: .medium))
                        .foregroundStyle(.ciForeground.opacity(0.78))
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ciForeground.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 10) {
                remoteAction("Deny", icon: "xmark", decision: .deny)
                remoteAction("Approve once", icon: "checkmark", decision: .approve)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.11), Color.ciSurface],
                startPoint: .topLeading,
                endPoint: .center
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(
                client.highlightedApprovalID == approval.id ? Color.orange.opacity(0.72) : Color.orange.opacity(0.18),
                lineWidth: client.highlightedApprovalID == approval.id ? 1.5 : 0.5
            )
        )
        .shadow(color: Color.orange.opacity(0.08), radius: 24, y: 12)
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

    @ViewBuilder
    private func remoteAction(
        _ title: String,
        icon: String,
        decision: RemoteApprovalDecision
    ) -> some View {
        if decision == .approve {
            actionButton(title, icon: icon, decision: decision)
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("companion.remote.\(decision.rawValue).\(approval.id)")
        } else {
            actionButton(title, icon: icon, decision: decision)
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityIdentifier("companion.remote.\(decision.rawValue).\(approval.id)")
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        decision: RemoteApprovalDecision
    ) -> some View {
        Button {
            selection = DecisionSelection(decision: decision)
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
                .frame(
                    minWidth: decision == .approve ? 0 : 116,
                    maxWidth: decision == .approve ? .infinity : 128,
                    minHeight: 48
                )
        }
        .disabled(client.busyRequestIDs.contains(approval.id))
    }
}
