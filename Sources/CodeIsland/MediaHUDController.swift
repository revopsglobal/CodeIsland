import Combine
import Foundation

/// Short-lived, low-cost feedback rendered at the notch for media and display
/// changes initiated through CodeIsland. It deliberately avoids private bezel
/// or display APIs; hardware-key brightness interception is not public macOS API.
@MainActor
final class MediaHUDController: ObservableObject {
    static let shared = MediaHUDController()

    struct Presentation: Equatable, Identifiable, Sendable {
        enum Kind: Equatable, Sendable {
            case nowPlaying
            case volume
            case brightness
        }

        let id: UUID
        let kind: Kind
        let title: String
        let subtitle: String?
        let symbol: String
        let level: Double?
        let artworkJPEG: Data?
    }

    @Published private(set) var presentation: Presentation?

    private let autoDismiss: Bool
    private let dismissDelay: TimeInterval
    private var dismissTask: Task<Void, Never>?

    init(autoDismiss: Bool = true, dismissDelay: TimeInterval = 2.6) {
        self.autoDismiss = autoDismiss
        self.dismissDelay = dismissDelay
    }

    func showNowPlaying(_ media: PersonalHubDataModel.NowPlaying) {
        let progress: Double?
        if let position = media.position, let duration = media.duration, duration > 0 {
            progress = min(max(position / duration, 0), 1)
        } else {
            progress = nil
        }
        show(.init(
            id: UUID(),
            kind: .nowPlaying,
            title: media.title,
            subtitle: [media.artist, media.album].filter { !$0.isEmpty }.joined(separator: " · "),
            symbol: media.isPlaying ? "waveform" : "pause.fill",
            level: progress,
            artworkJPEG: media.artworkJPEG
        ))
    }

    func showVolume(percent: Int, muted: Bool) {
        let clamped = min(max(percent, 0), 100)
        show(.init(
            id: UUID(),
            kind: .volume,
            title: muted ? "Muted" : "Volume",
            subtitle: muted ? nil : "\(clamped)%",
            symbol: muted || clamped == 0
                ? "speaker.slash.fill"
                : (clamped < 50 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"),
            level: Double(clamped) / 100,
            artworkJPEG: nil
        ))
    }

    func showBrightness(level: Double) {
        let clamped = min(max(level.isFinite ? level : 0, 0), 1)
        show(.init(
            id: UUID(),
            kind: .brightness,
            title: "Brightness",
            subtitle: "\(Int((clamped * 100).rounded()))%",
            symbol: "sun.max.fill",
            level: clamped,
            artworkJPEG: nil
        ))
    }

    func dismiss(id: UUID) {
        guard presentation?.id == id else { return }
        presentation = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    nonisolated static func shouldAnimateAmbient(
        reduceMotion: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> Bool {
        guard !reduceMotion else { return false }
        return thermalState == .nominal || thermalState == .fair
    }

    private func show(_ next: Presentation) {
        dismissTask?.cancel()
        presentation = next
        guard autoDismiss else { return }
        dismissTask = Task { [weak self] in
            let delay = UInt64(max(self?.dismissDelay ?? 0, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss(id: next.id)
        }
    }
}
