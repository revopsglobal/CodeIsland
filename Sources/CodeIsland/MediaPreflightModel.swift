import AppKit
@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import CoreMedia
import Foundation

enum MediaPreflightAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

struct MediaPreflightDevice: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case camera
        case microphone
    }

    let id: String
    let name: String
    let kind: Kind
}

enum MediaPreflightStopReason: Equatable, Sendable {
    case dismissed
    case background
    case interrupted
    case runtimeError
    case deviceDisconnected
    case permissionDenied
    case userStopped
}

struct MediaPreflightState: Equatable, Sendable {
    var cameraAuthorization: MediaPreflightAuthorization = .notDetermined
    var microphoneAuthorization: MediaPreflightAuthorization = .notDetermined
    var cameras: [MediaPreflightDevice] = []
    var microphones: [MediaPreflightDevice] = []
    var selectedCameraID: String?
    var selectedMicrophoneID: String?
    var rmsLevel = 0.0
    var peakLevel = 0.0
    var isRunning = false
    var stopReason: MediaPreflightStopReason?
    var errorMessage: String?

    var canStart: Bool {
        (cameraAuthorization == .authorized && !cameras.isEmpty)
            || (microphoneAuthorization == .authorized && !microphones.isEmpty)
    }

    var hasPermissionProblem: Bool {
        [.denied, .restricted].contains(cameraAuthorization)
            || [.denied, .restricted].contains(microphoneAuthorization)
    }

    mutating func updateAuthorization(
        camera: MediaPreflightAuthorization,
        microphone: MediaPreflightAuthorization
    ) {
        cameraAuthorization = camera
        microphoneAuthorization = microphone
    }

    mutating func reconcileDevices(
        cameras nextCameras: [MediaPreflightDevice],
        microphones nextMicrophones: [MediaPreflightDevice]
    ) {
        let cameraDisconnected = selectedCameraID.map { selected in
            !nextCameras.contains { $0.id == selected }
        } ?? false
        let microphoneDisconnected = selectedMicrophoneID.map { selected in
            !nextMicrophones.contains { $0.id == selected }
        } ?? false
        if isRunning && (cameraDisconnected || microphoneDisconnected) {
            stop(reason: .deviceDisconnected)
        }

        cameras = nextCameras
        microphones = nextMicrophones
        if selectedCameraID == nil || cameraDisconnected {
            selectedCameraID = nextCameras.first?.id
        }
        if selectedMicrophoneID == nil || microphoneDisconnected {
            selectedMicrophoneID = nextMicrophones.first?.id
        }
    }

    mutating func selectCamera(_ id: String) {
        guard cameras.contains(where: { $0.id == id }) else { return }
        selectedCameraID = id
    }

    mutating func selectMicrophone(_ id: String) {
        guard microphones.contains(where: { $0.id == id }) else { return }
        selectedMicrophoneID = id
    }

    mutating func markRunning() {
        isRunning = true
        stopReason = nil
        errorMessage = nil
    }

    mutating func updateLevels(samples: [Float]) {
        guard !samples.isEmpty else {
            rmsLevel = 0
            peakLevel = 0
            return
        }
        let sumSquares = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        }
        let rms = sqrt(sumSquares / Double(samples.count))
        let peak = samples.reduce(0.0) { max($0, Double(abs($1))) }
        rmsLevel = min(max(rms.isFinite ? rms : 0, 0), 1)
        peakLevel = min(max(peak.isFinite ? peak : 0, 0), 1)
    }

    mutating func stop(reason: MediaPreflightStopReason) {
        isRunning = false
        stopReason = reason
        rmsLevel = 0
        peakLevel = 0
    }
}

@MainActor
final class MediaPreflightModel: NSObject, ObservableObject {
    @Published private(set) var state = MediaPreflightState()

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.codeisland.media-preflight.session", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.codeisland.media-preflight.audio", qos: .userInitiated)
    private let audioOutput = AVCaptureAudioDataOutput()
    private let meterDelegate = MediaPreflightAudioMeter()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        meterDelegate.onSamples = { [weak self] samples in
            Task { @MainActor in
                self?.state.updateLevels(samples: samples)
            }
        }
        refreshAuthorization()
        refreshDevices()
        installObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func start() {
        Task { await requestPermissionsAndStart() }
    }

    func stop(reason: MediaPreflightStopReason) {
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        state.stop(reason: reason)
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func selectCamera(_ id: String) {
        let wasRunning = state.isRunning
        state.selectCamera(id)
        if wasRunning { configureAndStart() }
    }

    func selectMicrophone(_ id: String) {
        let wasRunning = state.isRunning
        state.selectMicrophone(id)
        if wasRunning { configureAndStart() }
    }

    func refreshAuthorization() {
        state.updateAuthorization(
            camera: Self.authorization(for: AVCaptureDevice.authorizationStatus(for: .video)),
            microphone: Self.authorization(for: AVCaptureDevice.authorizationStatus(for: .audio))
        )
    }

    func refreshDevices() {
        let cameras = Self.videoDevices()
            .map { MediaPreflightDevice(id: $0.uniqueID, name: $0.localizedName, kind: .camera) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let microphones = Self.audioDevices()
            .map { MediaPreflightDevice(id: $0.uniqueID, name: $0.localizedName, kind: .microphone) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let wasRunning = state.isRunning
        state.reconcileDevices(cameras: cameras, microphones: microphones)
        if wasRunning && !state.isRunning {
            stop(reason: .deviceDisconnected)
        }
    }

    nonisolated static func authorization(for status: AVAuthorizationStatus) -> MediaPreflightAuthorization {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .restricted
        }
    }

    private func requestPermissionsAndStart() async {
        if state.cameraAuthorization == .notDetermined {
            _ = await Self.requestAccess(for: .video)
        }
        if state.microphoneAuthorization == .notDetermined {
            _ = await Self.requestAccess(for: .audio)
        }
        refreshAuthorization()
        refreshDevices()
        guard state.canStart else {
            state.errorMessage = state.hasPermissionProblem
                ? "Enable Camera or Microphone access in System Settings → Privacy & Security."
                : "No camera or microphone is available."
            state.stop(reason: state.hasPermissionProblem ? .permissionDenied : .runtimeError)
            return
        }
        configureAndStart()
    }

    private func configureAndStart() {
        let devices = Self.videoDevices() + Self.audioDevices()
        let camera = state.cameraAuthorization == .authorized
            ? devices.first { $0.uniqueID == state.selectedCameraID }
            : nil
        let microphone = state.microphoneAuthorization == .authorized
            ? devices.first { $0.uniqueID == state.selectedMicrophoneID }
            : nil

        session.beginConfiguration()
        session.sessionPreset = .high
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        var addedInput = false
        if let camera, let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
            session.addInput(input)
            addedInput = true
        }
        if let microphone, let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) {
            session.addInput(input)
            addedInput = true
            audioOutput.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false,
            ]
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                audioOutput.setSampleBufferDelegate(meterDelegate, queue: audioQueue)
            }
        }
        session.commitConfiguration()

        guard addedInput else {
            state.errorMessage = "The selected camera and microphone are unavailable."
            state.stop(reason: .runtimeError)
            return
        }
        state.markRunning()
        let session = session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: .interrupted) }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: .runtimeError) }
        })
    }

    nonisolated private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated private static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    nonisolated private static func audioDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }
}

private final class MediaPreflightAudioMeter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onSamples: (([Float]) -> Void)?
    private var lastUpdate = 0.0

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastUpdate >= 0.05,
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        lastUpdate = now
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount >= MemoryLayout<Float>.size else { return }
        var samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
        let status = samples.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: bytes.baseAddress!
            )
        }
        guard status == kCMBlockBufferNoErr else { return }
        onSamples?(samples)
    }
}
