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
                        Text("Explicit decisions. Voice can never approve.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                                client: isMock ? nil : agentOps.client
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
        .accessibilityIdentifier("agentops.attention.screen")
    }

    private var visibleApprovals: [AgentOpsApprovalCard] {
        let pending = agentOps.approvals.filter { $0.status == .pending }
        return pending.isEmpty && isMock ? [Self.mockApproval] : pending
    }

    private var isAuthenticated: Bool {
        if case .authenticated = agentOps.auth.state {
            return true
        }
        return false
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
