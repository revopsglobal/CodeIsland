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
                            HStack(spacing: 8) {
                                Text("NEEDS YOU")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.2)
                                    .foregroundStyle(Color.orange)
                                Text("\(attentionItems.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.ciForeground.opacity(0.4))
                                Rectangle()
                                    .fill(Color.orange.opacity(0.25))
                                    .frame(height: 1)
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

                        // The rest of the queue as compact rows instead of a
                        // dropdown. A dropdown switches between equivalent
                        // options; these are not equivalent — one might be an
                        // rm -rf — so each shows its project, age and a command
                        // preview, and tapping promotes it into the card above.
                        ForEach(queuedItems) { item in
                            Button {
                                selectedAttentionID = item.id
                            } label: {
                                queuedRow(item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("companion.attention.queued.\(item.id)")
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

    /// Everything in the queue except the one already expanded in the card.
    private var queuedItems: [RemoteAttentionCardItem] {
        attentionItems.filter { $0.id != selectedAttention?.id }
    }

    @ViewBuilder
    private func queuedRow(_ item: RemoteAttentionCardItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(item.isDestructive ? Color.red : Color.orange)
                .frame(width: 30, height: 30)
                .background(
                    (item.isDestructive ? Color.red : Color.orange).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rowTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.ciForeground)
                    .lineLimit(1)
                if let subtitle = item.rowSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(item.isDestructive ? Color.red.opacity(0.9) : Color.ciForeground.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(item.createdAt, style: .relative)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.ciForeground.opacity(0.4))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color.ciForeground.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
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

    /// Project · tool, for the compact queue rows.
    var rowTitle: String {
        switch self {
        case .approval(let approval):
            let project = approval.workspace ?? approval.source
            return "\(project) · \(approval.tool)"
        case .question(let question):
            let project = question.workspace ?? question.source
            return "\(project) · Question"
        }
    }

    /// A one-line preview of what is being asked, so a queued row shows enough
    /// to triage without being promoted first.
    var rowSubtitle: String? {
        switch self {
        case .approval(let approval): return approval.detail
        case .question(let question): return question.prompts.first?.question
        }
    }

    var createdAt: Date {
        switch self {
        case .approval(let approval): return approval.createdAt
        case .question(let question): return question.createdAt
        }
    }

    /// Destructive queued rows preview their command in the danger colour, so
    /// "the second item is an rm -rf" is legible before you open it.
    var isDestructive: Bool {
        switch self {
        case .approval(let approval): return approval.risk == .destructive
        case .question: return false
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
                    .foregroundStyle(.orange)
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
                                .foregroundStyle(.orange)
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
                                        .foregroundStyle(isSelected(option, for: prompt) ? Color.orange : Color.ciForeground.opacity(0.38))
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
                                        ? Color.orange.opacity(0.12)
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
                .tint(.orange)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.10), Color.ciSurface],
                startPoint: .topLeading,
                endPoint: .center
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(
                client.highlightedQuestionID == question.id ? Color.orange.opacity(0.70) : Color.orange.opacity(0.16),
                lineWidth: client.highlightedQuestionID == question.id ? 1.5 : 0.5
            )
        )
        .shadow(color: Color.orange.opacity(0.08), radius: 24, y: 12)
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
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .tint(.orange)
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
        // Emphasis follows risk, not decision. Approving a destructive command
        // took exactly as many taps as denying it while looking considerably
        // more inviting: a wide filled bar against a narrow outline. For a
        // destructive request the safe action takes the filled treatment.
        if isEmphasised(decision) {
            actionButton(title, icon: icon, decision: decision)
                .buttonStyle(.borderedProminent)
                .tint(isDestructive ? .red : .orange)
                .accessibilityIdentifier("companion.remote.\(decision.rawValue).\(approval.id)")
        } else {
            actionButton(title, icon: icon, decision: decision)
                .buttonStyle(.bordered)
                .tint(isDestructive ? .secondary : .red)
                .accessibilityIdentifier("companion.remote.\(decision.rawValue).\(approval.id)")
        }
    }

    /// `nil` risk means an older Mac that predates classification — treated as
    /// unclassified, so emphasis stays on the historical default rather than
    /// implying the command is safe.
    private var isDestructive: Bool { approval.risk == .destructive }

    /// Which of the two actions gets the filled, full-width treatment.
    private func isEmphasised(_ decision: RemoteApprovalDecision) -> Bool {
        isDestructive ? decision == .deny : decision == .approve
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
                    minWidth: isEmphasised(decision) ? 0 : 116,
                    maxWidth: isEmphasised(decision) ? .infinity : 128,
                    minHeight: 48
                )
        }
        .disabled(client.busyRequestIDs.contains(approval.id))
    }
}
