import SwiftUI

struct AgentOpsTaskPresentation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let status: String
    let route: String
    let reviewer: String?
    let proofState: String
    let sources: [AgentOpsSourceHandle]

    init(summary: AgentOpsWorkSummary) {
        id = summary.id
        title = summary.title
        status = summary.lifecycle.status
        route = summary.routing.implementer?.rawValue ?? "auto"
        reviewer = summary.routing.reviewer
        proofState = summary.proof.state
        sources = summary.proof.handles
    }

    init(turnTask: AgentOpsTurnTaskSummary, sources: [AgentOpsSourceHandle]) {
        id = turnTask.id
        title = turnTask.title
        status = turnTask.status
        route = "selected by AgentOps"
        reviewer = nil
        proofState = "awaiting verified receipt"
        self.sources = sources
    }

    init(
        id: UUID,
        title: String,
        status: String,
        route: String,
        reviewer: String?,
        proofState: String,
        sources: [AgentOpsSourceHandle]
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.route = route
        self.reviewer = reviewer
        self.proofState = proofState
        self.sources = sources
    }
}

struct AgentOpsTaskView: View {
    let task: AgentOpsTaskPresentation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.title2.bold())
                    Text(task.id.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("agentops.work.detail.taskID")
                }

                AgentOpsTaskFact(
                    title: "Lifecycle",
                    value: task.status,
                    symbol: "arrow.triangle.branch"
                )
                AgentOpsTaskFact(
                    title: "Execution route",
                    value: task.route,
                    symbol: "point.3.connected.trianglepath.dotted"
                )
                AgentOpsTaskFact(
                    title: "Reviewer",
                    value: task.reviewer ?? "Not assigned",
                    symbol: "checkmark.shield"
                )
                AgentOpsTaskFact(
                    title: "Proof",
                    value: task.proofState,
                    symbol: "doc.text.magnifyingglass"
                )

                if !task.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Proof and sources")
                            .font(.headline)
                        ForEach(Array(task.sources.enumerated()), id: \.offset) {
                            _, source in
                            Link(destination: source.url) {
                                Label(
                                    source.label,
                                    systemImage: "arrow.up.right.square"
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 44,
                                    alignment: .leading
                                )
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                }
            }
            .padding(18)
        }
        .navigationTitle("AgentOps task")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("agentops.work.detail")
    }
}

private struct AgentOpsTaskFact: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value.replacingOccurrences(of: "_", with: " "))
                    .font(.body.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
