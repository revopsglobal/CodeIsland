import SwiftUI

struct AgentOpsVoiceOrb: View {
    let phase: VoiceSessionPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulses = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 196, height: 196)
                .scaleEffect(pulses && animates ? 1.12 : 0.96)
                .opacity(pulses && animates ? 0.38 : 0.7)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.62),
                            tint.opacity(0.9),
                            tint.opacity(0.48),
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 112
                    )
                )
                .frame(width: 144, height: 144)
                .shadow(color: tint.opacity(0.34), radius: 28, y: 12)

            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(
                    .variableColor.iterative,
                    options: reduceMotion ? .nonRepeating : .repeating,
                    isActive: animates
                )
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
            ) {
                pulses = true
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                pulses = false
            }
        }
    }

    private var animates: Bool {
        guard !reduceMotion else { return false }
        switch phase {
        case .listening, .userSpeaking, .thinking, .toolWorking, .speaking,
             .connecting, .reconnecting:
            return true
        case .idle, .paused, .failed:
            return false
        }
    }

    private var tint: Color {
        switch phase {
        case .failed:
            return .red
        case .paused:
            return .orange
        case .toolWorking:
            return .purple
        case .speaking:
            return .indigo
        case .userSpeaking:
            return .cyan
        case .reconnecting, .connecting:
            return .yellow
        case .idle, .listening, .thinking:
            return .blue
        }
    }

    private var symbol: String {
        switch phase {
        case .idle: return "waveform"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .listening: return "mic"
        case .userSpeaking: return "waveform"
        case .thinking: return "brain.head.profile"
        case .toolWorking: return "gearshape.2"
        case .speaking: return "speaker.wave.3"
        case .paused: return "pause"
        case .failed: return "exclamationmark"
        }
    }
}
