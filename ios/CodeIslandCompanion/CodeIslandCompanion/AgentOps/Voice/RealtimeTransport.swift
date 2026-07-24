import Foundation

@MainActor
protocol RealtimeTransport: AnyObject, Sendable {
    var onServerEvent: ((RealtimeServerEvent) -> Void)? { get set }
    var onConnectionStateChange: ((RealtimeConnectionState) -> Void)? {
        get set
    }

    func connect(with credential: RealtimeCredential) async throws
    func send(_ event: RealtimeClientEvent) throws
    func setMicrophoneEnabled(_ enabled: Bool)
    func disconnect() async
}

@MainActor
protocol WebRTCEngine: AnyObject {
    var onDataChannelMessage: ((Data) -> Void)? { get set }
    var onDataChannelOpen: (() -> Void)? { get set }
    var onConnectionStateChange: ((RealtimeConnectionState) -> Void)? {
        get set
    }

    func createPeerConnection() throws
    func addLocalAudioTrack() throws
    func createDataChannel(label: String) throws
    func createOffer() async throws -> String
    func setLocalDescription(sdp: String) async throws
    func setRemoteDescription(sdp: String) async throws
    func sendOnDataChannel(_ data: Data) throws
    func setMicrophoneEnabled(_ enabled: Bool)
    func close()
}

enum RealtimeTransportError: Error, Equatable {
    case noEngineConfigured
    case credentialExpired
    case notConnected
    case invalidSDPAnswer
    case sdpExchangeFailed(status: Int)
    case sessionConfigurationFailed
    case handshakeTimedOut
}

@MainActor
final class AgentOpsRealtimeTransport:
    RealtimeTransport,
    @unchecked Sendable
{
    var onServerEvent: ((RealtimeServerEvent) -> Void)?
    var onConnectionStateChange: ((RealtimeConnectionState) -> Void)?

    private(set) var callId: String?

    private let engine: WebRTCEngine?
    private let urlSession: URLSession
    private let callsEndpoint: URL
    private var isMicrophoneEnabled = true

    init(
        engine: WebRTCEngine?,
        urlSession: URLSession = .shared,
        callsEndpoint: URL = URL(
            string: "https://api.openai.com/v1/realtime/calls"
        )!
    ) {
        self.engine = engine
        self.urlSession = urlSession
        self.callsEndpoint = callsEndpoint
    }

    func connect(with credential: RealtimeCredential) async throws {
        guard let engine else {
            throw RealtimeTransportError.noEngineConfigured
        }
        try requireUsable(credential)

        engine.onConnectionStateChange = { [weak self] state in
            self?.onConnectionStateChange?(state)
        }
        engine.onDataChannelMessage = { [weak self] data in
            guard let event = RealtimeServerEvent.decode(from: data) else {
                return
            }
            self?.onServerEvent?(event)
        }

        try engine.createPeerConnection()
        try engine.addLocalAudioTrack()
        engine.setMicrophoneEnabled(isMicrophoneEnabled)
        try engine.createDataChannel(label: "oai-events")

        let offer = try await engine.createOffer()
        try requireUsable(credential)
        try await engine.setLocalDescription(sdp: offer)
        let answer = try await exchangeSDP(
            offer: offer,
            credential: credential
        )
        try requireUsable(credential)
        try await engine.setRemoteDescription(sdp: answer)
    }

    func send(_ event: RealtimeClientEvent) throws {
        guard let engine else {
            throw RealtimeTransportError.notConnected
        }
        try engine.sendOnDataChannel(event.toData())
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        isMicrophoneEnabled = enabled
        engine?.setMicrophoneEnabled(enabled)
    }

    func disconnect() async {
        engine?.close()
    }

    private func exchangeSDP(
        offer: String,
        credential: RealtimeCredential
    ) async throws -> String {
        try requireUsable(credential)
        var request = URLRequest(url: callsEndpoint)
        request.httpMethod = "POST"
        request.httpBody = Data(offer.utf8)
        request.setValue(
            "application/sdp",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "Bearer \(credential.clientSecret)",
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await urlSession.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw RealtimeTransportError.sdpExchangeFailed(
                status: (response as? HTTPURLResponse)?.statusCode ?? -1
            )
        }
        try requireUsable(credential)
        guard
            let answer = String(data: data, encoding: .utf8),
            !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw RealtimeTransportError.invalidSDPAnswer
        }
        callId = http.value(forHTTPHeaderField: "Location")
            .flatMap { $0.split(separator: "/").last.map(String.init) }
        return answer
    }

    private func requireUsable(
        _ credential: RealtimeCredential
    ) throws {
        guard credential.connectDeadline > Date() else {
            throw RealtimeTransportError.credentialExpired
        }
    }
}
