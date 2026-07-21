import AppKit
import AVFoundation
import SwiftUI

struct MediaPreflightView: View {
    let onDismiss: () -> Void
    @StateObject private var model = MediaPreflightModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera & microphone check")
                        .font(.system(size: 14, weight: .bold))
                    Text("Live on this Mac only")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    model.stop(reason: .dismissed)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .keyboardShortcut(.cancelAction)
            }
            .padding(14)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 12) {
                ZStack {
                    MacMediaPreview(session: model.session)
                    if model.state.cameraAuthorization != .authorized || model.state.cameras.isEmpty {
                        unavailableCamera
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Label(
                                model.state.isRunning ? "Live check" : "Stopped",
                                systemImage: model.state.isRunning ? "circle.fill" : "pause.fill"
                            )
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(model.state.isRunning ? Color.green : Color.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(.black.opacity(0.62), in: Capsule())
                            Spacer()
                        }
                        .padding(10)
                    }
                }
                .frame(height: 230)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

                HStack(spacing: 10) {
                    devicePicker(
                        title: "Camera",
                        symbol: "video.fill",
                        devices: model.state.cameras,
                        selection: model.state.selectedCameraID,
                        select: model.selectCamera
                    )
                    devicePicker(
                        title: "Microphone",
                        symbol: "mic.fill",
                        devices: model.state.microphones,
                        selection: model.state.selectedMicrophoneID,
                        select: model.selectMicrophone
                    )
                }

                microphoneMeter

                if let error = model.state.errorMessage {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        if model.state.hasPermissionProblem {
                            Button("Open Privacy Settings", action: openPrivacySettings)
                                .buttonStyle(.link)
                        }
                    }
                    .padding(9)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.orange)
                    Text("LOCAL ONLY · No frames or audio are recorded, encoded, uploaded, or added to Buddy snapshots.")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.state.isRunning ? "Stop" : "Start") {
                        if model.state.isRunning {
                            model.stop(reason: .userStopped)
                        } else {
                            model.start()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
        }
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
        .onDisappear { model.stop(reason: .dismissed) }
    }

    private var unavailableCamera: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(model.state.cameraAuthorization == .authorized
                ? "No camera is available"
                : "Camera access is off")
                .font(.system(size: 12, weight: .semibold))
        }
    }

    private func devicePicker(
        title: String,
        symbol: String,
        devices: [MediaPreflightDevice],
        selection: String?,
        select: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(.secondary)
            Picker(title, selection: Binding(
                get: { selection ?? "" },
                set: { select($0) }
            )) {
                if devices.isEmpty {
                    Text("Unavailable").tag("")
                } else {
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var microphoneMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("MICROPHONE", systemImage: "waveform")
                Spacer()
                Text(model.state.microphoneAuthorization == .authorized ? "INPUT LEVEL" : "ACCESS OFF")
            }
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.green, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: proxy.size.width * model.state.rmsLevel)
                    Rectangle()
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 2)
                        .offset(x: max(0, proxy.size.width * model.state.peakLevel - 2))
                }
            }
            .frame(height: 8)
        }
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct MacMediaPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CapturePreviewView {
        CapturePreviewView(session: session)
    }

    func updateNSView(_ nsView: CapturePreviewView, context: Context) {
        nsView.previewLayer.session = session
    }

    final class CapturePreviewView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
    }
}
