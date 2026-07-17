@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct MediaPreflightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = CompanionMediaPreflightModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CompanionMediaPreview(session: model.session)
                .ignoresSafeArea()

            if !model.hasCameraFeed {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 30, weight: .semibold))
                    Text(model.status)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(30)
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRIVATE PREFLIGHT")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.58))
                        Text("Camera & microphone")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Done") {
                        model.stop(reason: "Dismissed")
                        dismiss()
                    }
                    .accessibilityIdentifier("hub.camera.done")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(HubTheme.accent, in: Capsule())
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(model.isRunning ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(model.status)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        if model.cameras.count > 1 {
                            Menu {
                                ForEach(model.cameras) { camera in
                                    Button(camera.name) { model.selectCamera(camera.id) }
                                }
                            } label: {
                                Label("Camera", systemImage: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(HubTheme.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("MICROPHONE", systemImage: "waveform")
                            Spacer()
                            Text("INPUT LEVEL")
                        }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [.green, HubTheme.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .frame(width: proxy.size.width * model.rmsLevel)
                                Rectangle()
                                    .fill(.white.opacity(0.88))
                                    .frame(width: 2)
                                    .offset(x: max(0, proxy.size.width * model.peakLevel - 2))
                            }
                        }
                        .frame(height: 9)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(HubTheme.accent)
                        Text("LOCAL ONLY · Nothing is recorded, encoded, uploaded, or sent to your Mac.")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer(minLength: 0)
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hub.camera.preview")
        .onAppear { model.start() }
        .onDisappear { model.stop(reason: "Dismissed") }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.stop(reason: "Backgrounded") }
        }
    }
}

@MainActor
private final class CompanionMediaPreflightModel: NSObject, ObservableObject {
    struct Camera: Identifiable, Equatable {
        let id: String
        let name: String
    }

    @Published private(set) var cameras: [Camera] = []
    @Published private(set) var selectedCameraID: String?
    @Published private(set) var isRunning = false
    @Published private(set) var hasCameraFeed = false
    @Published private(set) var rmsLevel = 0.0
    @Published private(set) var peakLevel = 0.0
    @Published private(set) var status = "Checking access…"

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.codeisland.buddy.media-preflight", qos: .userInitiated)
    private let audioSessionQueue = DispatchQueue(label: "com.codeisland.buddy.media-session", qos: .userInitiated)
    private let audioEngine = AVAudioEngine()
    private var audioTapInstalled = false
    private var audioMeterGeneration = 0
    private var backgroundObserver: NSObjectProtocol?

    override init() {
        super.init()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop(reason: "Backgrounded") }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func start() {
        Task { await requestPermissionsAndStart() }
    }

    func stop(reason: String) {
        stopAudioMeter()
        isRunning = false
        rmsLevel = 0
        peakLevel = 0
        status = reason
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func selectCamera(_ id: String) {
        guard cameras.contains(where: { $0.id == id }) else { return }
        selectedCameraID = id
        configureAndStart()
    }

    private func requestPermissionsAndStart() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await Self.requestAccess(for: .video)
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await Self.requestAccess(for: .audio)
        }
        configureAndStart()
    }

    private func configureAndStart() {
        let cameraDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        cameras = cameraDevices.map { .init(id: $0.uniqueID, name: $0.localizedName) }
        if selectedCameraID == nil || !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = cameraDevices.first(where: { $0.position == .front })?.uniqueID
                ?? cameraDevices.first?.uniqueID
        }

        let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            ? cameraDevices.first { $0.uniqueID == selectedCameraID }
            : nil
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices.first
            : nil

        stopAudioMeter()
        session.beginConfiguration()
        session.sessionPreset = .high
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        hasCameraFeed = false
        if let camera, let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) {
            session.addInput(input)
            hasCameraFeed = true
        }
        session.commitConfiguration()

        guard hasCameraFeed || microphone != nil else {
            isRunning = false
            status = AVCaptureDevice.authorizationStatus(for: .video) == .denied
                ? "Enable Camera and Microphone in Settings"
                : "Camera and microphone unavailable"
            return
        }
        isRunning = true
        status = hasCameraFeed ? "LIVE · PRIVATE" : "MICROPHONE · PRIVATE"
        if microphone != nil { startAudioMeter() }
        let session = session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    private func startAudioMeter() {
        audioMeterGeneration += 1
        let generation = audioMeterGeneration
        audioSessionQueue.async { [weak self] in
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
                Task { @MainActor [weak self] in self?.installAudioMeter(generation: generation) }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, self.audioMeterGeneration == generation else { return }
                    if !self.hasCameraFeed { self.status = "Microphone unavailable" }
                }
            }
        }
    }

    private func installAudioMeter(generation: Int) {
        guard generation == audioMeterGeneration, isRunning, !audioTapInstalled else { return }
        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            Task { @MainActor [weak self] in self?.applyLevels(samples) }
        }
        audioTapInstalled = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopAudioMeter()
        }
    }

    private func stopAudioMeter() {
        audioMeterGeneration += 1
        if audioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioTapInstalled = false
        }
        audioEngine.stop()
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func applyLevels(_ samples: [Float]) {
        guard !samples.isEmpty else {
            rmsLevel = 0
            peakLevel = 0
            return
        }
        let sumSquares = samples.reduce(0.0) { $0 + Double($1 * $1) }
        rmsLevel = min(max(sqrt(sumSquares / Double(samples.count)), 0), 1)
        peakLevel = min(max(samples.reduce(0.0) { max($0, Double(abs($1))) }, 0), 1)
    }

    nonisolated private static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { continuation.resume(returning: $0) }
        }
    }
}

private struct CompanionMediaPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}
