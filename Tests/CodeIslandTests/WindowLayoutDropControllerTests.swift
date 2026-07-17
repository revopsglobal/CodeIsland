import XCTest
@testable import CodeIsland

final class WindowLayoutDropControllerTests: XCTestCase {
    private let primary = WindowLayoutScreen(
        id: "primary",
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875),
        topBarHeight: 37
    )
    private let external = WindowLayoutScreen(
        id: "external",
        frame: CGRect(x: 1_440, y: -200, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 1_440, y: -200, width: 1_920, height: 1_055),
        topBarHeight: 25
    )
    private let start = Date(timeIntervalSince1970: 1_000)

    func testHoverDelayShowsChooserAndDefaultsToMaximize() {
        var interaction = WindowLayoutDropInteraction()
        let point = CGPoint(x: primary.frame.midX, y: primary.frame.maxY - 10)

        interaction.updateDrag(
            point: point,
            screens: [primary],
            at: start,
            accessibilityAuthorized: true,
            targetEligible: true
        )
        XCTAssertEqual(interaction.phase, .hovering)

        interaction.updateDrag(
            point: point,
            screens: [primary],
            at: start.addingTimeInterval(WindowLayoutGeometry.hoverDelay + 0.01),
            accessibilityAuthorized: true,
            targetEligible: true
        )
        XCTAssertTrue(interaction.isChooserVisible)
        XCTAssertEqual(interaction.highlightedLayout, .maximize)
    }

    func testChooserUsesHysteresisThenCancelsOutsideRetention() {
        var interaction = choosingInteraction()
        let chooser = WindowLayoutGeometry.chooserFrame(for: primary)
        let withinHysteresis = CGPoint(x: chooser.minX - 20, y: chooser.midY)
        interaction.updateDrag(
            point: withinHysteresis,
            screens: [primary],
            at: start.addingTimeInterval(1),
            accessibilityAuthorized: true,
            targetEligible: true
        )
        XCTAssertEqual(interaction.phase, .choosing)

        interaction.updateDrag(
            point: CGPoint(x: chooser.minX - 100, y: chooser.midY),
            screens: [primary],
            at: start.addingTimeInterval(2),
            accessibilityAuthorized: true,
            targetEligible: true
        )
        XCTAssertEqual(interaction.phase, .idle)
        XCTAssertEqual(interaction.cancellation, .leftTarget)
    }

    func testReleaseReturnsHighlightedLayoutAndTargetDisplay() {
        var interaction = choosingInteraction(screen: external, screens: [primary, external])
        let chooser = WindowLayoutGeometry.chooserFrame(for: external)
        let rightThirdCell = CGPoint(
            x: chooser.minX + chooser.width * 0.72,
            y: chooser.minY + chooser.height * 0.25
        )
        interaction.updateDrag(
            point: rightThirdCell,
            screens: [primary, external],
            at: start.addingTimeInterval(1),
            accessibilityAuthorized: true,
            targetEligible: true
        )

        let selection = interaction.release()
        XCTAssertEqual(selection?.0, .rightThird)
        XCTAssertEqual(selection?.1.id, "external")
        XCTAssertEqual(interaction.phase, .idle)
    }

    func testGeometryCoversHalvesThirdsQuartersAndMaximize() {
        let visible = CGRect(x: 100, y: 50, width: 1_200, height: 800)
        XCTAssertEqual(
            WindowLayoutGeometry.frame(for: .left, in: visible),
            CGRect(x: 100, y: 50, width: 600, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutGeometry.frame(for: .rightThird, in: visible),
            CGRect(x: 900, y: 50, width: 400, height: 800)
        )
        XCTAssertEqual(
            WindowLayoutGeometry.frame(for: .topLeft, in: visible),
            CGRect(x: 100, y: 450, width: 600, height: 400)
        )
        XCTAssertEqual(
            WindowLayoutGeometry.frame(for: .bottomRight, in: visible),
            CGRect(x: 700, y: 50, width: 600, height: 400)
        )
        XCTAssertEqual(WindowLayoutGeometry.frame(for: .maximize, in: visible), visible)
    }

    func testMultipleDisplaysActivateOnlyTheDisplayUnderTheNotch() {
        var interaction = WindowLayoutDropInteraction()
        let point = CGPoint(x: external.frame.midX, y: external.frame.maxY - 10)
        interaction.updateDrag(
            point: point,
            screens: [primary, external],
            at: start,
            accessibilityAuthorized: true,
            targetEligible: true
        )
        XCTAssertEqual(interaction.screen?.id, "external")
    }

    func testAccessibilityDenialAndIneligibleWindowNeverShowChooser() {
        var interaction = WindowLayoutDropInteraction()
        let point = CGPoint(x: primary.frame.midX, y: primary.frame.maxY - 10)
        interaction.updateDrag(
            point: point,
            screens: [primary],
            at: start,
            accessibilityAuthorized: false,
            targetEligible: true
        )
        XCTAssertEqual(interaction.cancellation, .accessibilityDenied)
        XCTAssertFalse(interaction.isChooserVisible)

        interaction.updateDrag(
            point: point,
            screens: [primary],
            at: start,
            accessibilityAuthorized: true,
            targetEligible: false
        )
        XCTAssertEqual(interaction.cancellation, .ineligibleWindow)
        XCTAssertFalse(interaction.isChooserVisible)
    }

    func testReleaseBeforeHoverCompletesCancelsWithoutPlacement() {
        var interaction = WindowLayoutDropInteraction()
        let point = CGPoint(x: primary.frame.midX, y: primary.frame.maxY - 10)
        interaction.updateDrag(
            point: point,
            screens: [primary],
            at: start,
            accessibilityAuthorized: true,
            targetEligible: true
        )

        XCTAssertNil(interaction.release())
        XCTAssertEqual(interaction.cancellation, .releasedBeforeChoice)
    }

    func testCodeIslandProcessIsNeverAnEligibleWindowTarget() {
        XCTAssertFalse(WindowManagerController.isEligibleTarget(
            processIdentifier: 42,
            currentProcessIdentifier: 42
        ))
        XCTAssertFalse(WindowManagerController.isEligibleTarget(
            processIdentifier: 0,
            currentProcessIdentifier: 42
        ))
        XCTAssertTrue(WindowManagerController.isEligibleTarget(
            processIdentifier: 41,
            currentProcessIdentifier: 42
        ))
    }

    private func choosingInteraction(
        screen: WindowLayoutScreen? = nil,
        screens: [WindowLayoutScreen]? = nil
    ) -> WindowLayoutDropInteraction {
        let target = screen ?? primary
        let allScreens = screens ?? [target]
        let point = CGPoint(x: target.frame.midX, y: target.frame.maxY - 10)
        var interaction = WindowLayoutDropInteraction()
        interaction.updateDrag(
            point: point,
            screens: allScreens,
            at: start,
            accessibilityAuthorized: true,
            targetEligible: true
        )
        interaction.updateDrag(
            point: point,
            screens: allScreens,
            at: start.addingTimeInterval(WindowLayoutGeometry.hoverDelay + 0.01),
            accessibilityAuthorized: true,
            targetEligible: true
        )
        return interaction
    }
}
