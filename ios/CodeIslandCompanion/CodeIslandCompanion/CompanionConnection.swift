import Combine
import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class CompanionConnection: NSObject, ObservableObject {
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedPeer: MCPeerID?
    @Published private(set) var latestState: CompanionStatePayload? {
        didSet {
            watchBridge.publish(latestState)
        }
    }
    @Published private(set) var lastError: String?
    @Published private(set) var browsing = false
    @Published private(set) var bluetoothConnectedPeripheralName: String?
    @Published private(set) var lastStateReceivedAt: Date?
    @Published private(set) var isDemoMode = false

    private static let serviceType = "codeisland"
    private static let refreshAfterSeconds: TimeInterval = 8
    private static let reconnectAfterSeconds: TimeInterval = 24

    private let watchBridge = WatchBridge()
    private let bluetoothBridge = CompanionBluetoothCentral()
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private let mockStatePayload = CompanionConnection.mockStateFromLaunchArguments()
    private lazy var session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    private lazy var browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
    private var stateWatchdogTimer: Timer?
    private var connectedAt: Date?
    private var pendingReconnectPeer: MCPeerID?
    private var demoSequence: UInt64 = 9000
    var onStateReceived: ((CompanionStatePayload) -> Void)?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()
        session.delegate = self
        browser.delegate = self
        watchBridge.commandHandler = { [weak self] command in
            self?.send(command)
        }
        bluetoothBridge.onSummary = { [weak self] summary in
            self?.receiveBluetoothSummary(summary)
        }
        bluetoothBridge.$connectedPeripheralName
            .assign(to: &$bluetoothConnectedPeripheralName)
        bluetoothBridge.$lastError
            .compactMap { $0 }
            .assign(to: &$lastError)

        if let mockStatePayload {
            connectedPeer = MCPeerID(displayName: "CodeIsland Mock Mac")
            receiveState(mockStatePayload)
        }
    }

    deinit {
        stateWatchdogTimer?.invalidate()
    }

    func start() {
        guard !isDemoMode else { return }
        bluetoothBridge.start()
        guard mockStatePayload == nil else { return }
        startStateWatchdog()
        guard !browsing else { return }
        lastError = nil
        browsing = true
        browser.startBrowsingForPeers()
    }

    func stop() {
        if isDemoMode {
            exitDemoMode()
            return
        }
        guard mockStatePayload == nil else { return }
        browsing = false
        stateWatchdogTimer?.invalidate()
        stateWatchdogTimer = nil
        browser.stopBrowsingForPeers()
        session.disconnect()
        discoveredPeers = []
        connectedPeer = nil
        connectedAt = nil
        pendingReconnectPeer = nil
    }

    func connect(to peer: MCPeerID) {
        exitDemoMode()
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 12)
    }

    func enterDemoMode() {
        guard mockStatePayload == nil else { return }
        browser.stopBrowsingForPeers()
        session.disconnect()
        browsing = false
        discoveredPeers = []
        connectedAt = Date()
        connectedPeer = MCPeerID(displayName: "Code Island Demo")
        isDemoMode = true
        receiveState(Self.mockState(named: "question", sequence: nextDemoSequence()))
    }

    func cycleDemoState() {
        guard isDemoMode else { return }
        let states = ["question", "long", "interrupted", "idle"]
        let nextIndex = Int((demoSequence - 9000) % UInt64(states.count))
        receiveState(Self.mockState(named: states[nextIndex], sequence: nextDemoSequence()))
    }

    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        latestState = nil
        connectedPeer = nil
        connectedAt = nil
        lastStateReceivedAt = nil
        lastError = nil
    }

    func send(_ type: CompanionCommandType) {
        send(type, answer: nil)
    }

    func sendAnswer(_ answer: String) {
        send(.answerQuestion, answer: answer)
    }

    private func send(_ command: CompanionCommandPayload) {
        guard !session.connectedPeers.isEmpty else { return }

        do {
            let data = try encoder.encode(command)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func send(_ type: CompanionCommandType, answer: String?) {
        guard !session.connectedPeers.isEmpty else { return }
        let command = CompanionCommandPayload(
            type: type,
            sessionId: latestState?.sessionId,
            source: latestState?.source,
            answer: answer
        )
        send(command)
    }

    private func requestCurrentState(reason: String) {
        guard !session.connectedPeers.isEmpty else { return }
        let command = CompanionCommandPayload(type: .requestCurrentState)
        send(command)
    }

    private func receiveState(_ state: CompanionStatePayload) {
        lastStateReceivedAt = Date()
        latestState = state
        onStateReceived?(state)
    }

    private func startStateWatchdog() {
        guard stateWatchdogTimer == nil else { return }
        stateWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStateFreshness()
            }
        }
    }

    private func checkStateFreshness() {
        guard mockStatePayload == nil else { return }
        guard !isDemoMode else { return }
        guard let connectedPeer else { return }

        let now = Date()
        let reference = lastStateReceivedAt ?? connectedAt ?? now
        let age = now.timeIntervalSince(reference)

        if age >= Self.reconnectAfterSeconds {
            lastError = "Connected but no status updates for a while; reconnecting to Mac"
            pendingReconnectPeer = connectedPeer
            session.disconnect()
            self.connectedPeer = nil
            connectedAt = nil
            if !browsing {
                browsing = true
                browser.startBrowsingForPeers()
            }
            if discoveredPeers.contains(connectedPeer) {
                browser.invitePeer(connectedPeer, to: session, withContext: nil, timeout: 12)
            }
            return
        }

        if age >= Self.refreshAfterSeconds {
            requestCurrentState(reason: "stale-\(Int(age))s")
        }
    }

    func injectMockState(named name: String) {
        receiveState(Self.mockState(named: name, sequence: nextDemoSequence()))
    }

    private func nextDemoSequence() -> UInt64 {
        demoSequence += 1
        return demoSequence
    }

    private func receiveBluetoothSummary(_ summary: CompanionBluetoothSummary) {
        guard !isDemoMode else { return }

        if let current = latestState, current.sequence > summary.sequence {
            return
        }

        receiveState(summary.statePayload)
    }

    private static func mockStateFromLaunchArguments() -> CompanionStatePayload? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-CodeIslandCompanionMockState"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }

        return mockState(named: arguments[flagIndex + 1])
    }

    private static func mockState(named name: String, sequence: UInt64? = nil) -> CompanionStatePayload {
        let baseMessages = [
            CompanionMessagePreview(role: .user, text: "Help me write a novel"),
            CompanionMessagePreview(role: .assistant, text: "Sure, let me confirm the genre and length first, then start organizing the structure.")
        ]
        let resolvedSequence = sequence ?? 1000

        switch name.lowercased() {
        case "question":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-question",
                source: "claude",
                status: .waitingQuestion,
                toolName: "AskUserQuestion",
                workspaceName: "workspace",
                messages: baseMessages,
                pendingAction: .question,
                question: CompanionQuestionPayload(
                    header: "Genre",
                    question: "What genre of novel do you want to read?",
                    options: ["Urban / Realistic", "Sci-Fi", "Suspense / Mystery", "Fantasy / Xianxia"],
                    descriptions: [
                        "Modern city, workplace romance, everyday life",
                        "Future tech, AI, space, time travel",
                        "Crime investigation, puzzle-solving, psychological suspense",
                        "Magic worlds, cultivation, other-world adventures"
                    ],
                    index: 1,
                    total: 4,
                    allowsMultipleSelection: false
                ),
                updatedAt: Date()
            )
        case "interrupted":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-interrupted",
                source: "claude",
                status: .idle,
                toolName: nil,
                workspaceName: "workspace",
                messages: [
                    CompanionMessagePreview(role: .user, text: "Help me write a novel"),
                    CompanionMessagePreview(role: .assistant, text: "[Request interrupted by user]")
                ],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        case "long":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-long",
                source: "codex",
                status: .processing,
                toolName: "WebSearch",
                workspaceName: "workspace",
                messages: [
                    CompanionMessagePreview(role: .user, text: "Run through all the iPhone states prone to truncation yourself"),
                    CompanionMessagePreview(role: .assistant, text: "I'll use mock data to cover interruptions, questions, long text, and the Live Activity display, focusing on localization, scroll regions, the recent-activity font size, and whether buttons get cramped."),
                    CompanionMessagePreview(role: .assistant, text: "This is a deliberately long recent activity, used to confirm it won't get clipped by the card in iPhone portrait, and that nested internal scrolling won't cut off part of the content.")
                ],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        case "multi":
            let now = Date()
            let previews = [
                CompanionSessionPreview(sessionId: "s1", source: "claude", status: .waitingQuestion, toolName: "AskUserQuestion", workspaceName: "code-island", message: "What genre of novel do you want to read?", messages: [
                    CompanionMessagePreview(role: .user, text: "Help me write a novel"),
                    CompanionMessagePreview(role: .assistant, text: "Sure, let's confirm the **genre** and length first. What genre of novel do you want to read?")
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s2", source: "codex", status: .processing, toolName: "WebSearch", workspaceName: "apple-companion", message: "Searching for information", messages: [
                    CompanionMessagePreview(role: .user, text: "Look up how to use SwiftUI `safeAreaInsets`"),
                    CompanionMessagePreview(role: .assistant, text: "Searching for information, one moment.")
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s3", source: "cursor", status: .running, toolName: "Edit", workspaceName: "ios", message: "Editing ContentView", messages: [
                    CompanionMessagePreview(role: .user, text: "Make the session card notch-style"),
                    CompanionMessagePreview(role: .assistant, text: "Editing `ContentView.swift`, aligning status coloring and multi-turn transcripts.")
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s4", source: "gemini", status: .waitingApproval, toolName: "Bash", workspaceName: "scripts", message: "Requesting to run a command", messages: [
                    CompanionMessagePreview(role: .assistant, text: "Requesting to run `npm run build`. Approve?")
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s5", source: "kimi", status: .idle, toolName: nil, workspaceName: "docs", message: nil, updatedAt: now),
                CompanionSessionPreview(sessionId: "s6", source: "qwen", status: .processing, toolName: "Read", workspaceName: "server", message: "Reading config", messages: [
                    CompanionMessagePreview(role: .user, text: "Check the server config"),
                    CompanionMessagePreview(role: .assistant, text: "Reading `config.yaml`…")
                ], updatedAt: now)
            ]
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-multi",
                source: "claude",
                status: .processing,
                toolName: "AskUserQuestion",
                workspaceName: "code-island",
                messages: [
                    CompanionMessagePreview(role: .user, text: "Help me make the dashboard's session cards match the notch"),
                    CompanionMessagePreview(role: .assistant, text: "Sure, I'll align the **status coloring**, `#id`, time-ago, and the `$ thinking` work row."),
                    CompanionMessagePreview(role: .assistant, text: "Committed and pushed; the landscape hero now shows the main session's 3 most recent transcripts.")
                ],
                pendingAction: nil,
                question: nil,
                sessions: previews,
                updatedAt: now
            )
        default:
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-idle",
                source: "codex",
                status: .idle,
                toolName: nil,
                workspaceName: "workspace",
                messages: [],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        }
    }
}

extension CompanionConnection: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !self.discoveredPeers.contains(peerID) else { return }
            self.discoveredPeers.append(peerID)
            if self.pendingReconnectPeer == peerID {
                self.pendingReconnectPeer = nil
                self.connect(to: peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
            if self.connectedPeer == peerID {
                self.connectedPeer = nil
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.browsing = false
            self.lastError = error.localizedDescription
        }
    }
}

extension CompanionConnection: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.connectedAt = Date()
                self.requestCurrentState(reason: "peer-connected")
            case .notConnected:
                if self.connectedPeer == peerID {
                    self.connectedPeer = nil
                }
                self.connectedAt = nil
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                self.receiveState(try self.decoder.decode(CompanionStatePayload.self, from: data))
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
