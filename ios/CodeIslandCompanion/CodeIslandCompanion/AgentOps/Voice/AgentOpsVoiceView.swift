import SwiftUI

struct AgentOpsVoiceView: View {
    @ObservedObject var model: AgentOpsVoiceViewModel
    let topPadding: CGFloat

    @EnvironmentObject private var agentOps: AgentOpsRootStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var email = ""
    @State private var signInCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if model.isMock || isAuthenticated {
                    voiceSurface
                } else {
                    authSurface
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, topPadding)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .task {
            model.configure(rootStore: agentOps)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AgentOps Voice")
                    .font(
                        dynamicTypeSize.isAccessibilitySize
                            ? .title3.bold()
                            : .title.bold()
                    )
                    .accessibilityIdentifier("agentops.voice.screen")
                if !dynamicTypeSize.isAccessibilitySize {
                    Text("Wiki context. Durable work. Exact proof.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.blue)
                .accessibilityLabel("Private AgentOps session")
        }
    }

    private var voiceSurface: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text(model.stateTitle)
                    .font(.headline)
                    .accessibilityIdentifier("agentops.voice.state")
                Text(model.stateDetail)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.stateTitle)

            if dynamicTypeSize.isAccessibilitySize {
                voiceControls
            } else {
                AgentOpsVoiceOrb(phase: model.phase)
            }

            if model.isRecording {
                Button {
                    model.finishRecording()
                } label: {
                    Label("Stop & send", systemImage: "arrow.up.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityIdentifier("agentops.voice.send")
            } else if model.canStart {
                Button {
                    Task { await model.startVoice() }
                } label: {
                    Label("Start voice", systemImage: "mic.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("agentops.voice.start")
            }

            if !dynamicTypeSize.isAccessibilitySize {
                voiceControls
            }

            if let result = model.latestResult {
                AgentOpsVoiceResultCard(result: result)
            }

            VoiceTranscriptView(entries: model.transcriptEntries)

            Text("Voice playback is AI-generated.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("agentops.voice.aiDisclosure")
        }
    }

    private var voiceControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                controlButtons
            }
            VStack(spacing: 10) {
                controlButtons
            }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        Button(action: model.stopResponse) {
            Label("Cancel", systemImage: "xmark.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .disabled(!model.canStop)
        .accessibilityIdentifier("agentops.voice.stop")

        Button {
            Task { await model.endVoice() }
        } label: {
            Label("End", systemImage: "phone.down.fill")
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.bordered)
        .disabled(!model.isRunning)
        .accessibilityIdentifier("agentops.voice.end")
    }

    private var authSurface: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch agentOps.auth.state {
            case .restoring:
                ProgressView("Restoring AgentOps sign-in…")
                    .frame(maxWidth: .infinity, minHeight: 180)

            case .signedOut, .failed:
                Label("Sign in to AgentOps", systemImage: "person.badge.key")
                    .font(.title3.bold())
                Text(
                    "Use your RevOps Global email. The link returns to this app and the session stays in Keychain."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                TextField("Work email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .accessibilityIdentifier("agentops.auth.email")

                Button {
                    Task { await agentOps.auth.sendMagicLink(to: email) }
                } label: {
                    Text("Email sign-in link")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("agentops.auth.sendLink")

                if case .failed(let message) = agentOps.auth.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("agentops.auth.error")
                }

            case .linkSent(let sentEmail):
                Label("Check your email", systemImage: "envelope.badge")
                    .font(.title3.bold())
                Text(
                    "Open the AgentOps sign-in link sent to \(sentEmail), or enter the numeric code from that email."
                )
                    .font(.body)

                TextField("Sign-in code", text: $signInCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .padding(14)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .onChange(of: signInCode) { _, newValue in
                        signInCode = String(newValue.filter(\.isNumber).prefix(10))
                    }
                    .accessibilityIdentifier("agentops.auth.code")

                Button {
                    Task {
                        await agentOps.verifyCode(signInCode, for: sentEmail)
                    }
                } label: {
                    Text("Verify code")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(6...10).contains(signInCode.count))
                .accessibilityIdentifier("agentops.auth.verifyCode")

                if let codeError = agentOps.auth.codeError {
                    Text(codeError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("agentops.auth.codeError")
                }

                Button("Use another email") {
                    email = ""
                    signInCode = ""
                    Task { await agentOps.auth.restore() }
                }
                .buttonStyle(.bordered)

            case .authenticated:
                EmptyView()
            }
        }
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("agentops.auth.surface")
    }

    private var isAuthenticated: Bool {
        if case .authenticated = agentOps.auth.state {
            return true
        }
        return false
    }
}

private struct AgentOpsVoiceResultCard: View {
    let result: AgentOpsTurnResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(kindTitle, systemImage: kindSymbol)
                    .font(.headline)
                    .foregroundStyle(kindTint)
                Spacer()
                Text(result.kind.rawValue.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }

            Text(result.displayText)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let task = result.task {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                    Text(task.id.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("agentops.voice.taskID")
                }
            }

            if !result.sources.isEmpty {
                Divider()
                ForEach(Array(result.sources.enumerated()), id: \.offset) {
                    _, source in
                    Link(destination: source.url) {
                        Label(source.label, systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(kindTint.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "agentops.voice.result.\(result.kind.rawValue)"
        )
    }

    private var kindTitle: String {
        switch result.kind {
        case .answer: return "Answer"
        case .clarify: return "Clarification"
        case .durableWork: return "Work captured"
        }
    }

    private var kindSymbol: String {
        switch result.kind {
        case .answer: return "checkmark.bubble"
        case .clarify: return "questionmark.bubble"
        case .durableWork: return "tray.and.arrow.down"
        }
    }

    private var kindTint: Color {
        switch result.kind {
        case .answer: return .blue
        case .clarify: return .orange
        case .durableWork: return .green
        }
    }
}
