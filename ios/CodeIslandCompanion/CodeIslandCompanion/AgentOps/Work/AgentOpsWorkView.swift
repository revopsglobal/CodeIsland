import SwiftUI

struct AgentOpsWorkView: View {
    @EnvironmentObject private var agentOps: AgentOpsRootStore
    private let mockScenario = AgentOpsVoiceMockScenario.from(
        arguments: ProcessInfo.processInfo.arguments
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Work")
                            .font(.largeTitle.bold())
                        Text("Canonical AgentOps tasks and proof state.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if presentations.isEmpty {
                        ContentUnavailableView(
                            "No work yet",
                            systemImage: "checklist",
                            description: Text(
                                "Durable voice requests will appear here with their exact AgentOps UUID."
                            )
                        )
                        .frame(minHeight: 360)
                        .accessibilityIdentifier("agentops.work.empty")
                    } else {
                        ForEach(presentations) { task in
                            NavigationLink {
                                AgentOpsTaskView(task: task)
                            } label: {
                                AgentOpsWorkRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let error = agentOps.refreshError, mockScenario == nil {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("agentops.work.error")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .refreshable {
                guard mockScenario == nil else { return }
                await agentOps.refreshWork()
            }
        }
        .task {
            guard mockScenario == nil, isAuthenticated else { return }
            await agentOps.refreshWork()
        }
        .accessibilityIdentifier("agentops.work.screen")
    }

    private var presentations: [AgentOpsTaskPresentation] {
        var values = agentOps.work.map(AgentOpsTaskPresentation.init(summary:))
        if let result = agentOps.latestTurnResult,
           let task = result.task,
           !values.contains(where: { $0.id == task.id }) {
            values.insert(
                AgentOpsTaskPresentation(
                    turnTask: task,
                    sources: result.sources
                ),
                at: 0
            )
        }
        if values.isEmpty, mockScenario != nil {
            values = [Self.mockTask]
        }
        return values
    }

    private var isAuthenticated: Bool {
        if case .authenticated = agentOps.auth.state {
            return true
        }
        return false
    }

    private static let mockTask = AgentOpsTaskPresentation(
        turnTask: AgentOpsTurnTaskSummary(
            id: UUID(uuidString: "e7e843c5-733d-4492-a863-1c337684653b")!,
            title: "Ship AgentOps native voice mode",
            status: "in_progress"
        ),
        sources: [
            AgentOpsSourceHandle(
                kind: "task",
                label: "Open in AgentOps",
                url: URL(
                    string: "https://agentops.revopsglobal.com/fleet/tasks/e7e843c5-733d-4492-a863-1c337684653b"
                )!
            ),
        ]
    )
}

private struct AgentOpsWorkRow: View {
    let task: AgentOpsTaskPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(task.id.uuidString.lowercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Label(
                        task.status.replacingOccurrences(of: "_", with: " "),
                        systemImage: "circle.fill"
                    )
                    Text(task.route)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "agentops.work.task.\(task.id.uuidString.lowercased())"
        )
    }
}
