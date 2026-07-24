import Foundation
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class VoiceSessionCoordinatorTests: XCTestCase {
    func testCredentialExpiryBoundsConnectButCallLifetimeOwnsRotation() async {
        let transport = FakeRealtimeTransport(name: "primary")
        let coordinator = VoiceSessionCoordinator(
            credentialProvider: { _ in
                RealtimeCredential(
                    sessionId: "session-1",
                    clientSecret: "ephemeral",
                    model: "gpt-realtime",
                    connectDeadline: Date().addingTimeInterval(60)
                )
            },
            callLifetimeSeconds: 55 * 60,
            makeTransport: { transport }
        )

        let result = await coordinator.start(voice: "marin")

        XCTAssertEqual(result, .success)
        XCTAssertEqual(coordinator.rotationInterval, 55 * 60)
        XCTAssertGreaterThan(
            coordinator.scheduledRotationDate?.timeIntervalSinceNow ?? 0,
            54 * 60
        )
        await coordinator.teardown()
    }

    func testRotationIsMakeBeforeBreakAndPreservesPausedMicrophone() async {
        let sequence = TransportSequence()
        let primary = FakeRealtimeTransport(name: "primary", sequence: sequence)
        let candidate = FakeRealtimeTransport(name: "candidate", sequence: sequence)
        var transports = [primary, candidate]
        let coordinator = VoiceSessionCoordinator(
            credentialProvider: { _ in
                RealtimeCredential(
                    sessionId: UUID().uuidString,
                    clientSecret: "ephemeral",
                    model: "gpt-realtime",
                    connectDeadline: Date().addingTimeInterval(120)
                )
            },
            makeTransport: { transports.removeFirst() }
        )
        coordinator.setMicrophoneEnabled(false)

        let startResult = await coordinator.start(voice: "marin")
        XCTAssertEqual(startResult, .success)
        await coordinator.rotate(voice: "marin")

        XCTAssertEqual(primary.microphoneValues.first, false)
        XCTAssertEqual(candidate.microphoneValues.first, false)
        XCTAssertEqual(sequence.events, [
            "primary.connect",
            "primary.ready",
            "candidate.connect",
            "candidate.ready",
            "primary.disconnect",
        ])
        await coordinator.teardown()
    }

    func testReconnectUsesNewTransportAndKeepsMicrophonePaused() async {
        let primary = FakeRealtimeTransport(name: "primary")
        let replacement = FakeRealtimeTransport(name: "replacement")
        var transports = [primary, replacement]
        let coordinator = VoiceSessionCoordinator(
            credentialProvider: { _ in
                RealtimeCredential(
                    sessionId: UUID().uuidString,
                    clientSecret: "ephemeral",
                    model: "gpt-realtime",
                    connectDeadline: Date().addingTimeInterval(120)
                )
            },
            makeTransport: { transports.removeFirst() }
        )
        coordinator.setMicrophoneEnabled(false)
        let startResult = await coordinator.start(voice: nil)
        XCTAssertEqual(startResult, .success)

        let reconnected = expectation(description: "reconnected")
        coordinator.scheduleReconnect(after: 0, voice: nil) { result in
            XCTAssertEqual(result, .success)
            reconnected.fulfill()
        }
        await fulfillment(of: [reconnected], timeout: 2)

        XCTAssertEqual(replacement.microphoneValues.first, false)
        XCTAssertEqual(primary.disconnectCount, 1)
        await coordinator.teardown()
    }
}

@MainActor
private final class TransportSequence {
    var events: [String] = []
}

@MainActor
private final class FakeRealtimeTransport: RealtimeTransport, @unchecked Sendable {
    var onServerEvent: ((RealtimeServerEvent) -> Void)?
    var onConnectionStateChange: ((RealtimeConnectionState) -> Void)?

    let name: String
    let sequence: TransportSequence?
    var sent: [RealtimeClientEvent] = []
    var microphoneValues: [Bool] = []
    var disconnectCount = 0

    init(name: String, sequence: TransportSequence? = nil) {
        self.name = name
        self.sequence = sequence
    }

    func connect(with credential: RealtimeCredential) async throws {
        sequence?.events.append("\(name).connect")
        onConnectionStateChange?(.connecting)
        onServerEvent?(.sessionCreated(sessionId: credential.sessionId))
    }

    func send(_ event: RealtimeClientEvent) throws {
        sent.append(event)
        if case .sessionUpdate = event {
            sequence?.events.append("\(name).ready")
            onServerEvent?(.sessionUpdated)
            onConnectionStateChange?(.connected)
        }
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        microphoneValues.append(enabled)
    }

    func disconnect() async {
        disconnectCount += 1
        sequence?.events.append("\(name).disconnect")
    }
}
