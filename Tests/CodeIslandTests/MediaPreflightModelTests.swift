import XCTest
@testable import CodeIsland

final class MediaPreflightModelTests: XCTestCase {
    func testPermissionTransitionsPreserveExplicitDeniedState() {
        var state = MediaPreflightState()
        XCTAssertEqual(state.cameraAuthorization, .notDetermined)
        XCTAssertEqual(state.microphoneAuthorization, .notDetermined)

        state.updateAuthorization(camera: .authorized, microphone: .denied)
        state.reconcileDevices(
            cameras: [.init(id: "camera", name: "Camera", kind: .camera)],
            microphones: []
        )

        XCTAssertEqual(state.cameraAuthorization, .authorized)
        XCTAssertEqual(state.microphoneAuthorization, .denied)
        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.hasPermissionProblem)
    }

    func testDeviceEnumerationSelectsDefaultsAndPreservesExplicitSelection() {
        var state = MediaPreflightState()
        let cameras = [
            MediaPreflightDevice(id: "camera-a", name: "Studio Display", kind: .camera),
            MediaPreflightDevice(id: "camera-b", name: "iPhone Camera", kind: .camera),
        ]
        let microphones = [
            MediaPreflightDevice(id: "mic-a", name: "MacBook Microphone", kind: .microphone),
            MediaPreflightDevice(id: "mic-b", name: "Desk Mic", kind: .microphone),
        ]

        state.reconcileDevices(cameras: cameras, microphones: microphones)
        XCTAssertEqual(state.selectedCameraID, "camera-a")
        XCTAssertEqual(state.selectedMicrophoneID, "mic-a")

        state.selectCamera("camera-b")
        state.selectMicrophone("mic-b")
        state.reconcileDevices(cameras: Array(cameras.reversed()), microphones: Array(microphones.reversed()))
        XCTAssertEqual(state.selectedCameraID, "camera-b")
        XCTAssertEqual(state.selectedMicrophoneID, "mic-b")
    }

    func testSelectedDeviceDisconnectStopsCaptureAndChoosesAvailableFallback() {
        var state = MediaPreflightState()
        state.updateAuthorization(camera: .authorized, microphone: .authorized)
        state.reconcileDevices(
            cameras: [
                .init(id: "camera-a", name: "Camera A", kind: .camera),
                .init(id: "camera-b", name: "Camera B", kind: .camera),
            ],
            microphones: [.init(id: "mic-a", name: "Mic", kind: .microphone)]
        )
        state.selectCamera("camera-b")
        state.markRunning()

        state.reconcileDevices(
            cameras: [.init(id: "camera-a", name: "Camera A", kind: .camera)],
            microphones: [.init(id: "mic-a", name: "Mic", kind: .microphone)]
        )

        XCTAssertFalse(state.isRunning)
        XCTAssertEqual(state.stopReason, .deviceDisconnected)
        XCTAssertEqual(state.selectedCameraID, "camera-a")
    }

    func testRMSAndPeakLevelsAreNormalizedAndClamped() {
        var state = MediaPreflightState()
        state.updateLevels(samples: [-2, -0.5, 0.5, 2])

        XCTAssertEqual(state.peakLevel, 1, accuracy: 0.0001)
        XCTAssertEqual(state.rmsLevel, 1, accuracy: 0.0001)

        state.updateLevels(samples: [0.25, -0.25])
        XCTAssertEqual(state.peakLevel, 0.25, accuracy: 0.0001)
        XCTAssertEqual(state.rmsLevel, 0.25, accuracy: 0.0001)

        state.updateLevels(samples: [])
        XCTAssertEqual(state.peakLevel, 0, accuracy: 0.0001)
        XCTAssertEqual(state.rmsLevel, 0, accuracy: 0.0001)
    }

    func testInterruptionDismissalAndBackgroundAlwaysStopAndResetMeter() {
        for reason in [
            MediaPreflightStopReason.interrupted,
            .dismissed,
            .background,
            .runtimeError,
        ] {
            var state = MediaPreflightState()
            state.markRunning()
            state.updateLevels(samples: [0.8])
            state.stop(reason: reason)

            XCTAssertFalse(state.isRunning)
            XCTAssertEqual(state.stopReason, reason)
            XCTAssertEqual(state.rmsLevel, 0)
            XCTAssertEqual(state.peakLevel, 0)
        }
    }
}
