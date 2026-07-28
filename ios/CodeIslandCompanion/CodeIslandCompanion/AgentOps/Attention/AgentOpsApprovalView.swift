import SwiftUI

@MainActor
final class AgentOpsApprovalViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case resolving
        case resolved(AgentOpsApprovalStatus)
        case failed(String)
    }

    let approval: AgentOpsApprovalCard
    @Published private(set) var state: State = .idle
    @Published var denialReason = ""

    private let now: () -> Date
    private let resolve:
        @MainActor (AgentOpsApprovalResolutionRequest) async throws
            -> AgentOpsApprovalResolutionResponse
    private let onResolved:
        @MainActor (AgentOpsApprovalStatus) -> Void

    init(
        approval: AgentOpsApprovalCard,
        now: @escaping () -> Date = Date.init,
        resolve: @escaping @MainActor (AgentOpsApprovalResolutionRequest)
            async throws -> AgentOpsApprovalResolutionResponse,
        onResolved: @escaping @MainActor (AgentOpsApprovalStatus) -> Void = { _ in }
    ) {
        self.approval = approval
        self.now = now
        self.resolve = resolve
        self.onResolved = onResolved
    }

    var canResolve: Bool {
        let stateAllowsResolution: Bool
        switch state {
        case .idle, .failed:
            stateAllowsResolution = true
        case .resolving, .resolved:
            stateAllowsResolution = false
        }
        return stateAllowsResolution
            && approval.status == .pending
            && approval.requiresExplicitTap
            && approval.expiresAt > now()
    }

    func resolveFromVisibleTap(
        _ decision: AgentOpsApprovalStatus,
        decisionNote: String? = nil
    ) async {
        guard canResolve, decision != .pending else {
            if approval.expiresAt <= now() {
                state = .failed("This approval expired. Refresh Attention.")
            }
            return
        }
        state = .resolving
        let normalizedNote = decisionNote?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try await resolve(
                AgentOpsApprovalResolutionRequest(
                    actionDigest: approval.actionDigest,
                    resolution: decision,
                    interaction: .onScreenTap,
                    decisionNote: normalizedNote?.isEmpty == false
                        ? normalizedNote
                        : nil
                )
            )
            guard
                response.resolved,
                response.approvalId == approval.id,
                response.status == decision
            else {
                state = .failed(
                    "AgentOps did not confirm that decision. Refresh Attention."
                )
                return
            }
            state = .resolved(decision)
            onResolved(decision)
        } catch let error as AgentOpsClientError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(
                "AgentOps could not record that decision. Try again."
            )
        }
    }

    private static func message(for error: AgentOpsClientError) -> String {
        if case .server(let code, _) = error {
            switch code {
            case "approval_digest_mismatch":
                return "This approval changed. Refresh Attention before deciding."
            case "approval_expired":
                return "This approval expired. Refresh Attention."
            case "approval_already_resolved":
                return "This approval was already resolved. Refresh Attention."
            case "approval_resolution_not_recorded":
                return "That didn’t go through. Try again."
            default:
                break
            }
        }
        return "AgentOps could not record that decision. Try again."
    }
}

struct AgentOpsApprovalView: View {
    @StateObject private var model: AgentOpsApprovalViewModel
    @State private var isShowingDenial = false

    init(
        approval: AgentOpsApprovalCard,
        client: AgentOpsClient?,
        onResolved: @escaping @MainActor (AgentOpsApprovalStatus) -> Void = { _ in }
    ) {
        _model = StateObject(
            wrappedValue: AgentOpsApprovalViewModel(
                approval: approval,
                resolve: { request in
                    guard let client else {
                        throw AgentOpsClientError.invalidRequest
                    }
                    return try await client.resolveApproval(
                        id: approval.id,
                        request: request
                    )
                },
                onResolved: onResolved
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Approval required", systemImage: "hand.raised.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Text(model.approval.type.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            exactField(title: "TARGET", value: model.approval.target)
            Text(model.approval.consequence)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Expires") {
                Text(model.approval.expiresAt, style: .relative)
            }
            .font(.footnote)

            Label(
                "For safety, approval requires one tap here.",
                systemImage: "hand.tap"
            )
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)

            DisclosureGroup("Technical details") {
                VStack(alignment: .leading, spacing: 10) {
                    exactField(
                        title: "TASK UUID",
                        value: model.approval.taskId.uuidString.lowercased()
                    )
                    exactField(
                        title: "ACTION DIGEST",
                        value: model.approval.actionDigest
                    )
                    Text("Voice cannot approve this action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            .font(.footnote)

            if isShowingDenial {
                TextField(
                    "Optional denial reason",
                    text: $model.denialReason,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .accessibilityIdentifier(
                    "agentops.approval.\(model.approval.id.uuidString.lowercased()).reason"
                )

                HStack(spacing: 10) {
                    Button("Cancel") {
                        isShowingDenial = false
                    }
                    .buttonStyle(.bordered)

                    Button("Confirm deny") {
                        Task {
                            await model.resolveFromVisibleTap(
                                .rejected,
                                decisionNote: model.denialReason
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!model.canResolve)
                    .accessibilityIdentifier(
                        "agentops.approval.\(model.approval.id.uuidString.lowercased()).deny"
                    )
                }
            } else {
                HStack(spacing: 10) {
                    Button("Deny") {
                        isShowingDenial = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!model.canResolve)

                    Button("Approve once") {
                        Task {
                            await model.resolveFromVisibleTap(.approved)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!model.canResolve)
                    .accessibilityIdentifier(
                        "agentops.approval.\(model.approval.id.uuidString.lowercased()).approve"
                    )
                }
            }

            resolutionState
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.orange.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "agentops.attention.approval.\(model.approval.id.uuidString.lowercased())"
        )
    }

    private func exactField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(title == "TARGET" ? .title3.weight(.semibold) : .caption.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var resolutionState: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .resolving:
            ProgressView("Recording exact decision…")
        case .resolved(let status):
            Label(
                status == .approved ? "Approved" : "Denied",
                systemImage: status == .approved ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .font(.footnote.weight(.semibold))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }
}
