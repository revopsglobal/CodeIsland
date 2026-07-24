import Foundation

enum VoiceSessionConnectionResult: Equatable, Sendable {
    case success
    case failure(String)
}

private actor VoiceSessionMutex {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withLock<T>(_ operation: () async -> T) async -> T {
        await lock()
        let result = await operation()
        unlock()
        return result
    }

    private func lock() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func unlock() {
        if waiters.isEmpty {
            locked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
final class VoiceSessionCoordinator: @unchecked Sendable {
    nonisolated static let defaultCallLifetimeSeconds: TimeInterval = 55 * 60
    private static let handshakeTimeoutSeconds: TimeInterval = 15
    private static let rotationRetrySeconds: TimeInterval = 30

    typealias CredentialProvider =
        @MainActor (String?) async throws -> RealtimeCredential

    private let credentialProvider: CredentialProvider
    private let instructions: () -> String
    private let toolDefinitions: [RealtimeToolDefinition]
    private let makeTransport: @MainActor () -> RealtimeTransport
    private let mutex = VoiceSessionMutex()

    let rotationInterval: TimeInterval
    private(set) var scheduledRotationDate: Date?

    private var generationCounter = 0
    private var currentGeneration = -1
    private var primaryTransport: RealtimeTransport?
    private var rotatingTransport: RealtimeTransport?
    private var rotationTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var lastVoice: String?
    private var isMicrophoneEnabled = true

    var onServerEvent: ((RealtimeServerEvent) -> Void)?
    var onCallEstablished: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?

    init(
        credentialProvider: @escaping CredentialProvider,
        instructions: @escaping () -> String = {
            AgentOpsRealtimeProtocol.instructions
        },
        toolDefinitions: [RealtimeToolDefinition] =
            AgentOpsRealtimeProtocol.toolDefinitions,
        callLifetimeSeconds: TimeInterval =
            VoiceSessionCoordinator.defaultCallLifetimeSeconds,
        makeTransport: @escaping @MainActor () -> RealtimeTransport
    ) {
        self.credentialProvider = credentialProvider
        self.instructions = instructions
        self.toolDefinitions = toolDefinitions
        rotationInterval = callLifetimeSeconds
        self.makeTransport = makeTransport
    }

    func start(voice: String?) async -> VoiceSessionConnectionResult {
        lastVoice = voice
        return await mutex.withLock {
            await self.connectNewPrimary(voice: voice)
        }
    }

    func send(_ event: RealtimeClientEvent) throws {
        guard let primaryTransport else {
            throw RealtimeTransportError.notConnected
        }
        try primaryTransport.send(event)
    }

    func setMicrophoneEnabled(_ enabled: Bool) {
        isMicrophoneEnabled = enabled
        primaryTransport?.setMicrophoneEnabled(enabled)
        rotatingTransport?.setMicrophoneEnabled(enabled)
    }

    func scheduleReconnect(
        after delay: TimeInterval,
        voice: String?,
        completion: @escaping (VoiceSessionConnectionResult) -> Void
    ) {
        lastVoice = voice ?? lastVoice
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }
            let result = await self.mutex.withLock {
                await self.connectNewPrimary(
                    voice: voice ?? self.lastVoice
                )
            }
            completion(result)
        }
    }

    func rotate(voice: String?) async {
        let selectedVoice = voice ?? lastVoice
        lastVoice = selectedVoice
        await mutex.withLock {
            guard self.primaryTransport != nil else { return }
            do {
                let credential = try await self.credentialProvider(
                    selectedVoice
                )
                let candidateGeneration = self.nextGeneration()
                let candidate = try await self.establishAndHandshake(
                    credential: credential,
                    voice: selectedVoice,
                    generation: candidateGeneration
                ) { transport in
                    self.rotatingTransport = transport
                }
                let previous = self.primaryTransport
                self.currentGeneration = candidateGeneration
                self.primaryTransport = candidate
                self.rotatingTransport = nil
                self.scheduleRotation()
                await previous?.disconnect()
                self.onCallEstablished?()
            } catch {
                let candidate = self.rotatingTransport
                self.rotatingTransport = nil
                await candidate?.disconnect()
                self.scheduleRotationRetry()
            }
        }
    }

    func teardown() async {
        rotationTimer?.invalidate()
        rotationTimer = nil
        scheduledRotationDate = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        await mutex.withLock {
            self.currentGeneration = -1
            let primary = self.primaryTransport
            let rotating = self.rotatingTransport
            self.primaryTransport = nil
            self.rotatingTransport = nil
            await primary?.disconnect()
            await rotating?.disconnect()
        }
    }

    private func connectNewPrimary(
        voice: String?
    ) async -> VoiceSessionConnectionResult {
        do {
            let credential = try await credentialProvider(voice)
            let generation = nextGeneration()
            let candidate = try await establishAndHandshake(
                credential: credential,
                voice: voice,
                generation: generation
            ) { _ in }
            let previous = primaryTransport
            currentGeneration = generation
            primaryTransport = candidate
            scheduleRotation()
            await previous?.disconnect()
            onCallEstablished?()
            return .success
        } catch {
            return .failure(String(describing: error))
        }
    }

    private func establishAndHandshake(
        credential: RealtimeCredential,
        voice: String?,
        generation: Int,
        track: (RealtimeTransport) -> Void
    ) async throws -> RealtimeTransport {
        guard credential.connectDeadline > Date() else {
            throw RealtimeTransportError.credentialExpired
        }
        let transport = makeTransport()
        transport.setMicrophoneEnabled(isMicrophoneEnabled)
        track(transport)

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            var timeoutTask: Task<Void, Never>?

            let finish: (Result<Void, Error>) -> Void = { result in
                guard !finished else { return }
                finished = true
                timeoutTask?.cancel()
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            transport.onServerEvent = { event in
                switch event {
                case .sessionCreated:
                    do {
                        try transport.send(
                            .sessionUpdate(
                                instructions: self.instructions(),
                                tools: self.toolDefinitions,
                                voice: voice
                            )
                        )
                    } catch {
                        finish(.failure(error))
                    }
                case .sessionUpdated:
                    finish(.success(()))
                case .error:
                    finish(
                        .failure(
                            RealtimeTransportError
                                .sessionConfigurationFailed
                        )
                    )
                default:
                    break
                }
            }
            transport.onConnectionStateChange = { state in
                if case .failed = state {
                    finish(.failure(RealtimeTransportError.notConnected))
                }
            }

            timeoutTask = Task { @MainActor in
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        Self.handshakeTimeoutSeconds * 1_000_000_000
                    )
                )
                guard !Task.isCancelled else { return }
                finish(.failure(RealtimeTransportError.handshakeTimedOut))
            }

            Task { @MainActor in
                do {
                    guard credential.connectDeadline > Date() else {
                        throw RealtimeTransportError.credentialExpired
                    }
                    try await transport.connect(with: credential)
                } catch {
                    finish(.failure(error))
                }
            }
        }

        transport.onServerEvent = { [weak self] event in
            self?.deliver(event, generation: generation)
        }
        transport.onConnectionStateChange = { [weak self] state in
            self?.handleConnectionState(
                state,
                generation: generation
            )
        }
        return transport
    }

    private func deliver(
        _ event: RealtimeServerEvent,
        generation: Int
    ) {
        guard generation == currentGeneration else { return }
        onServerEvent?(event)
    }

    private func handleConnectionState(
        _ state: RealtimeConnectionState,
        generation: Int
    ) {
        guard generation == currentGeneration else { return }
        switch state {
        case .disconnected:
            onDisconnected?(nil)
        case .failed(let reason):
            onDisconnected?(reason)
        case .connecting, .connected:
            break
        }
    }

    private func nextGeneration() -> Int {
        generationCounter += 1
        return generationCounter
    }

    private func scheduleRotation() {
        rotationTimer?.invalidate()
        let date = Date().addingTimeInterval(rotationInterval)
        scheduledRotationDate = date
        rotationTimer = Timer.scheduledTimer(
            withTimeInterval: rotationInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.rotate(voice: self.lastVoice)
            }
        }
    }

    private func scheduleRotationRetry() {
        rotationTimer?.invalidate()
        scheduledRotationDate = Date().addingTimeInterval(
            Self.rotationRetrySeconds
        )
        rotationTimer = Timer.scheduledTimer(
            withTimeInterval: Self.rotationRetrySeconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.rotate(voice: self.lastVoice)
            }
        }
    }
}
