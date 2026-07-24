import AVFoundation
import Foundation

func speakerFirstWebRTCOptions(
    from existing: AVAudioSession.CategoryOptions
) -> AVAudioSession.CategoryOptions {
    existing.union(.defaultToSpeaker)
}

#if canImport(WebRTC)
import WebRTC

@MainActor
final class StaselWebRTCEngine: NSObject, WebRTCEngine {
    var onDataChannelMessage: ((Data) -> Void)?
    var onDataChannelOpen: (() -> Void)?
    var onConnectionStateChange: ((RealtimeConnectionState) -> Void)?

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?

    override init() {
        let audioConfiguration = RTCAudioSessionConfiguration.webRTC()
        audioConfiguration.categoryOptions = speakerFirstWebRTCOptions(
            from: audioConfiguration.categoryOptions
        )
        RTCAudioSessionConfiguration.setWebRTC(audioConfiguration)
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
    }

    func createPeerConnection() throws {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.iceServers = [
            RTCIceServer(
                urlStrings: ["stun:stun.l.google.com:19302"]
            ),
        ]
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        guard
            let connection = factory.peerConnection(
                with: configuration,
                constraints: constraints,
                delegate: self
            )
        else {
            throw RealtimeTransportError.notConnected
        }
        peerConnection = connection
        onConnectionStateChange?(.connecting)
    }

    func addLocalAudioTrack() throws {
        guard let peerConnection else {
            throw RealtimeTransportError.notConnected
        }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false",
            ],
            optionalConstraints: nil
        )
        let source = factory.audioSource(with: constraints)
        let track = factory.audioTrack(
            with: source,
            trackId: "agentops-audio"
        )
        localAudioTrack = track
        peerConnection.add(track, streamIds: ["agentops-stream"])
    }

    func createDataChannel(label: String) throws {
        guard let peerConnection else {
            throw RealtimeTransportError.notConnected
        }
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        guard
            let channel = peerConnection.dataChannel(
                forLabel: label,
                configuration: configuration
            )
        else {
            throw RealtimeTransportError.notConnected
        }
        channel.delegate = self
        dataChannel = channel
    }

    func createOffer() async throws -> String {
        guard let peerConnection else {
            throw RealtimeTransportError.notConnected
        }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false",
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description.sdp)
                } else {
                    continuation.resume(
                        throwing: RealtimeTransportError.invalidSDPAnswer
                    )
                }
            }
        }
    }

    func setLocalDescription(sdp: String) async throws {
        guard let peerConnection else {
            throw RealtimeTransportError.notConnected
        }
        let description = RTCSessionDescription(type: .offer, sdp: sdp)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescription(sdp: String) async throws {
        guard let peerConnection else {
            throw RealtimeTransportError.notConnected
        }
        let description = RTCSessionDescription(type: .answer, sdp: sdp)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func sendOnDataChannel(_ data: Data) throws {
        guard
            let dataChannel,
            dataChannel.readyState == .open,
            dataChannel.sendData(
                RTCDataBuffer(data: data, isBinary: false)
            )
        else {
            throw RealtimeTransportError.notConnected
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        localAudioTrack?.isEnabled = enabled
    }

    func close() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        localAudioTrack = nil
        onConnectionStateChange?(.disconnected)
    }
}

extension StaselWebRTCEngine: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {}

    nonisolated func peerConnectionShouldNegotiate(
        _ peerConnection: RTCPeerConnection
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didOpen dataChannel: RTCDataChannel
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCPeerConnectionState
    ) {
        Task { @MainActor in
            switch newState {
            case .new, .connecting:
                self.onConnectionStateChange?(.connecting)
            case .connected:
                self.onConnectionStateChange?(.connected)
            case .disconnected, .closed:
                self.onConnectionStateChange?(.disconnected)
            case .failed:
                self.onConnectionStateChange?(
                    .failed("WebRTC peer connection failed")
                )
            @unknown default:
                break
            }
        }
    }
}

extension StaselWebRTCEngine: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(
        _ dataChannel: RTCDataChannel
    ) {
        Task { @MainActor in
            if dataChannel.readyState == .open {
                self.onDataChannelOpen?()
            }
        }
    }

    nonisolated func dataChannel(
        _ dataChannel: RTCDataChannel,
        didReceiveMessageWith buffer: RTCDataBuffer
    ) {
        let data = buffer.data
        Task { @MainActor in
            self.onDataChannelMessage?(data)
        }
    }
}
#endif

@MainActor
func makeAgentOpsWebRTCEngine() -> WebRTCEngine? {
    #if canImport(WebRTC)
    StaselWebRTCEngine()
    #else
    nil
    #endif
}
