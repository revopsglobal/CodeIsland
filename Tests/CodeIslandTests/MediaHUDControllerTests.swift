import XCTest
@testable import CodeIsland

@MainActor
final class MediaHUDControllerTests: XCTestCase {
    func testVolumeAndBrightnessPresentationsClampLevels() throws {
        let controller = MediaHUDController(autoDismiss: false)

        controller.showVolume(percent: 140, muted: false)
        let volume = try XCTUnwrap(controller.presentation)
        XCTAssertEqual(volume.kind, .volume)
        XCTAssertEqual(volume.level, 1)
        XCTAssertEqual(volume.title, "Volume")

        controller.showBrightness(level: -0.5)
        let brightness = try XCTUnwrap(controller.presentation)
        XCTAssertEqual(brightness.kind, .brightness)
        XCTAssertEqual(brightness.level, 0)
    }

    func testStaleDismissNeverHidesANewerPresentation() throws {
        let controller = MediaHUDController(autoDismiss: false)
        controller.showVolume(percent: 25, muted: false)
        let firstID = try XCTUnwrap(controller.presentation?.id)
        controller.showVolume(percent: 75, muted: false)
        let secondID = try XCTUnwrap(controller.presentation?.id)

        controller.dismiss(id: firstID)
        XCTAssertEqual(controller.presentation?.id, secondID)

        controller.dismiss(id: secondID)
        XCTAssertNil(controller.presentation)
    }

    func testAmbientMotionRespectsAccessibilityAndThermalPressure() {
        XCTAssertTrue(MediaHUDController.shouldAnimateAmbient(
            reduceMotion: false,
            thermalState: .nominal
        ))
        XCTAssertFalse(MediaHUDController.shouldAnimateAmbient(
            reduceMotion: true,
            thermalState: .nominal
        ))
        XCTAssertFalse(MediaHUDController.shouldAnimateAmbient(
            reduceMotion: false,
            thermalState: .serious
        ))
        XCTAssertFalse(MediaHUDController.shouldAnimateAmbient(
            reduceMotion: false,
            thermalState: .critical
        ))
    }
}
