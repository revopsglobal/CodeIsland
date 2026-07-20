import AppKit
import SwiftUI

enum TeleprompterStopReason: Equatable {
    case paused
    case manualScroll
    case reachedEnd
    case closed
}

struct TeleprompterPlaybackState: Equatable {
    static let wordsPerMinuteRange = 60...240
    static let fontSizeRange = 24.0...72.0

    let wordCount: Int
    private(set) var wordOffset: Double = 0
    private(set) var wordsPerMinute: Int
    private(set) var fontSize: Double
    private(set) var isPlaying = false
    private(set) var stopReason: TeleprompterStopReason?
    private(set) var lastTick: Date?

    init(text: String, wordsPerMinute: Int = 120, fontSize: Double = 42) {
        wordCount = text.split(whereSeparator: \Character.isWhitespace).count
        self.wordsPerMinute = wordsPerMinute.clamped(to: Self.wordsPerMinuteRange)
        self.fontSize = fontSize.clamped(to: Self.fontSizeRange)
    }

    var currentWordIndex: Int {
        guard wordCount > 0 else { return 0 }
        return min(Int(wordOffset.rounded(.down)), wordCount - 1)
    }

    var currentSegment: Int { currentWordIndex / 12 }

    var progress: Double {
        guard wordCount > 1 else { return wordCount == 1 ? 1 : 0 }
        return min(max(wordOffset / Double(wordCount - 1), 0), 1)
    }

    var hasReachedEnd: Bool {
        wordCount == 0 || wordOffset >= Double(max(wordCount - 1, 0))
    }

    mutating func play(at date: Date) {
        guard wordCount > 0 else {
            stopReason = .reachedEnd
            return
        }
        if hasReachedEnd { wordOffset = 0 }
        isPlaying = true
        stopReason = nil
        lastTick = date
    }

    mutating func pause(at date: Date, reason: TeleprompterStopReason = .paused) {
        advance(to: date)
        isPlaying = false
        stopReason = reason
        lastTick = nil
    }

    mutating func advance(to date: Date) {
        guard isPlaying, let lastTick else { return }
        let elapsed = max(date.timeIntervalSince(lastTick), 0)
        self.lastTick = date
        wordOffset += elapsed * Double(wordsPerMinute) / 60
        if wordOffset >= Double(max(wordCount - 1, 0)) {
            wordOffset = Double(max(wordCount - 1, 0))
            isPlaying = false
            stopReason = .reachedEnd
            self.lastTick = nil
        }
    }

    mutating func setWordsPerMinute(_ value: Int, at date: Date) {
        advance(to: date)
        wordsPerMinute = value.clamped(to: Self.wordsPerMinuteRange)
    }

    mutating func setFontSize(_ value: Double) {
        fontSize = value.clamped(to: Self.fontSizeRange)
    }

    mutating func close(at date: Date) {
        pause(at: date, reason: .closed)
    }
}

enum TeleprompterSharingPrivacy {
    static let requestedSharingType: NSWindow.SharingType = .none
    static let disclosure = "Screen-share hiding requested. Full-display capture may still include this window."
}

@MainActor
final class TeleprompterPlaybackModel: ObservableObject {
    static let wordsPerMinuteKey = "codeisland.teleprompter.wordsPerMinute.v1"
    static let fontSizeKey = "codeisland.teleprompter.fontSize.v1"

    let text: String
    let segments: [String]
    @Published private(set) var state: TeleprompterPlaybackState

    private let defaults: UserDefaults

    init(text: String, defaults: UserDefaults = .standard) {
        self.text = text
        self.defaults = defaults
        let savedWPM = defaults.object(forKey: Self.wordsPerMinuteKey) as? Int ?? 120
        let savedFontSize = defaults.object(forKey: Self.fontSizeKey) as? Double ?? 42
        state = TeleprompterPlaybackState(
            text: text,
            wordsPerMinute: savedWPM,
            fontSize: savedFontSize
        )
        let words = text.split(whereSeparator: \Character.isWhitespace).map(String.init)
        segments = stride(from: 0, to: words.count, by: 12).map { index in
            words[index..<min(index + 12, words.count)].joined(separator: " ")
        }
    }

    var isPlaying: Bool { state.isPlaying }
    var currentSegment: Int { state.currentSegment }
    var wordsPerMinute: Int { state.wordsPerMinute }
    var fontSize: Double { state.fontSize }

    func togglePlayback(at date: Date = Date()) {
        if state.isPlaying {
            state.pause(at: date)
        } else {
            state.play(at: date)
        }
    }

    func tick(at date: Date = Date()) {
        state.advance(to: date)
    }

    func manualScroll(at date: Date = Date()) {
        guard state.isPlaying else { return }
        state.pause(at: date, reason: .manualScroll)
    }

    func setWordsPerMinute(_ value: Int, at date: Date = Date()) {
        state.setWordsPerMinute(value, at: date)
        defaults.set(state.wordsPerMinute, forKey: Self.wordsPerMinuteKey)
    }

    func setFontSize(_ value: Double) {
        state.setFontSize(value)
        defaults.set(state.fontSize, forKey: Self.fontSizeKey)
    }

    func close(at date: Date = Date()) {
        state.close(at: date)
    }
}

@MainActor
final class TeleprompterWindowController: NSObject, NSWindowDelegate {
    static let shared = TeleprompterWindowController()

    private var window: NSWindow?
    private var playback: TeleprompterPlaybackModel?
    private var scrollMonitor: Any?

    func show(text: String) {
        cleanup(closeWindow: true)

        let playback = TeleprompterPlaybackModel(text: text)
        let view = MacTeleprompterView(playback: playback) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeIsland Teleprompter"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        // Best-effort window exclusion. Full-display capture can still include it,
        // so the UI never claims that the script is guaranteed private.
        window.sharingType = TeleprompterSharingPrivacy.requestedSharingType
        window.center()
        window.contentView = NSHostingView(rootView: view)

        self.playback = playback
        self.window = window
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard self?.window?.isKeyWindow == true else { return event }
            self?.playback?.manualScroll()
            return event
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        cleanup(closeWindow: false)
    }

    private func cleanup(closeWindow: Bool) {
        playback?.close()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        if closeWindow {
            window?.delegate = nil
            window?.close()
        }
        window = nil
        playback = nil
    }
}

private struct MacTeleprompterView: View {
    @ObservedObject var playback: TeleprompterPlaybackModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            script
            controls
        }
        .background(Color.black)
        .task(id: playback.isPlaying) {
            guard playback.isPlaying else { return }
            while !Task.isCancelled, playback.isPlaying {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                playback.tick()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.viewfinder")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("TELEPROMPTER")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.4)
                Label(
                    TeleprompterSharingPrivacy.disclosure,
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Text("\(Int(playback.state.progress * 100))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Button("Done", action: close)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var script: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(Array(playback.segments.enumerated()), id: \.offset) { index, segment in
                        Text(segment)
                            .font(.system(size: playback.fontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(index < playback.currentSegment ? .white.opacity(0.22) : .white)
                            .lineSpacing(13)
                            .frame(maxWidth: 760, alignment: .leading)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 50)
                .padding(.vertical, 90)
            }
            .onChange(of: playback.currentSegment) { _, value in
                withAnimation(.linear(duration: 0.45)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                playback.setFontSize(playback.fontSize - 2)
            } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .accessibilityLabel("Smaller text")

            Button {
                playback.togglePlayback()
            } label: {
                Label(
                    playback.isPlaying ? "Pause" : "Play",
                    systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                )
                .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Stepper(
                "\(playback.wordsPerMinute) WPM",
                value: Binding(
                    get: { playback.wordsPerMinute },
                    set: { playback.setWordsPerMinute($0) }
                ),
                in: TeleprompterPlaybackState.wordsPerMinuteRange,
                step: 15
            )
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .frame(width: 160)

            Button {
                playback.setFontSize(playback.fontSize + 2)
            } label: {
                Image(systemName: "textformat.size.larger")
            }
            .accessibilityLabel("Larger text")

            Spacer()

            if playback.state.stopReason == .manualScroll {
                Label("Paused for manual scroll", systemImage: "hand.draw.fill")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            } else {
                Text("Scroll anytime to pause")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.42))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
