import SwiftUI

struct AgentOpsAttentionView: View {
    @EnvironmentObject private var agentOps: AgentOpsRootStore
    private let isMock = AgentOpsVoiceMockScenario.from(
        arguments: ProcessInfo.processInfo.arguments
    ) != nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attention")
                            .font(.largeTitle.bold())
                            .accessibilityIdentifier(
                                "agentops.attention.screen"
                            )
                        Text("Review decisions that need your tap.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let push = agentOps.pushCoordinator {
                        notificationOptIn(
                            permissionGranted: push.permissionGranted,
                            registrationError: push.registrationError,
                            requestAccess: {
                                await push.requestNotificationAccess()
                            }
                        )
                    } else if isMock {
                        notificationOptIn(
                            permissionGranted: nil,
                            registrationError: nil,
                            requestAccess: {}
                        )
                    }

                    if visibleApprovals.isEmpty {
                        ContentUnavailableView(
                            "Nothing needs you",
                            systemImage: "checkmark.shield",
                            description: Text(
                                "AgentOps approvals and questions will appear here."
                            )
                        )
                        .frame(minHeight: 360)
                        .accessibilityIdentifier("agentops.attention.empty")
                    } else {
                        ForEach(visibleApprovals) { approval in
                            AgentOpsApprovalView(
                                approval: approval,
                                client: isMock ? nil : agentOps.client,
                                onResolved: { status in
                                    agentOps.markApprovalResolved(
                                        id: approval.id,
                                        status: status
                                    )
                                }
                            )
                        }
                    }

                    if let error = agentOps.refreshError, !isMock {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .refreshable {
                guard !isMock else { return }
                await agentOps.refreshApprovals()
            }
        }
        .task {
            guard !isMock, isAuthenticated else { return }
            await agentOps.refreshApprovals()
        }
    }

    private var visibleApprovals: [AgentOpsApprovalCard] {
        let pending = agentOps.approvals.filter { $0.status == .pending }
        let values = pending.isEmpty && isMock ? [Self.mockApproval] : pending
        guard case .approval(let highlighted) = agentOps.navigationTarget else {
            return values
        }
        return values.sorted {
            ($0.id == highlighted ? 0 : 1)
                < ($1.id == highlighted ? 0 : 1)
        }
    }

    private var isAuthenticated: Bool {
        if case .authenticated = agentOps.auth.state {
            return true
        }
        return false
    }

    @ViewBuilder
    private func notificationOptIn(
        permissionGranted: Bool?,
        registrationError: String?,
        requestAccess: @escaping @MainActor () async -> Void
    ) -> some View {
        if permissionGranted != true {
            Button {
                Task { await requestAccess() }
            } label: {
                Label(
                    permissionGranted == false
                        ? "Review AgentOps alert permission"
                        : "Enable AgentOps alerts",
                    systemImage: "bell.badge"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("agentops.attention.enableAlerts")
        } else {
            Label("AgentOps alerts enabled", systemImage: "bell.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }

        if let error = registrationError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private static let mockApproval = AgentOpsApprovalCard(
        id: UUID(uuidString: "b5ef124a-5b67-4e5e-b8f2-dd0de5f40114")!,
        taskId: UUID(uuidString: "e7e843c5-733d-4492-a863-1c337684653b")!,
        type: "production_deploy",
        status: .pending,
        target: "voice.agentops.revopsglobal.com",
        consequence: "Deploy the verified AgentOps voice gateway to production.",
        expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
        actionDigest: String(repeating: "a", count: 64),
        requiresExplicitTap: true
    )
}
