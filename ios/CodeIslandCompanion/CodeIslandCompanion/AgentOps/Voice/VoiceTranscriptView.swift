import SwiftUI

struct VoiceTranscriptEntry: Identifiable, Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct VoiceTranscriptView: View {
    let entries: [VoiceTranscriptEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Conversation", systemImage: "text.bubble")
                .font(.headline)

            if entries.isEmpty {
                Text("Your conversation will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(roleLabel(entry.role))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        roleTint(entry.role).opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agentops.voice.transcript")
    }

    private func roleLabel(_ role: VoiceTranscriptEntry.Role) -> String {
        switch role {
        case .user: return "YOU"
        case .assistant: return "AGENTOPS"
        case .system: return "STATUS"
        }
    }

    private func roleTint(_ role: VoiceTranscriptEntry.Role) -> Color {
        switch role {
        case .user: return .cyan
        case .assistant: return .indigo
        case .system: return .orange
        }
    }
}
