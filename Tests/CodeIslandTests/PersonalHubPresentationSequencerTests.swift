import XCTest

final class PersonalHubPresentationSequencerTests: XCTestCase {
    func testToolsDoesNotUseSheetsAttachedToTransientNotchPanel() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent("Sources/CodeIsland/PersonalHubMacView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains(".sheet(isPresented: $showingRackEditor)"),
            "A sheet attached to the auto-collapsing notch panel can crash AppKit during SheetBridge teardown."
        )
        XCTAssertFalse(
            source.contains(".confirmationDialog("),
            "Tools actions must use an in-panel review instead of a SwiftUI confirmation sheet."
        )
        XCTAssertFalse(
            source.contains(".sheet(isPresented: $showsMediaPreflight)"),
            "Camera preflight must stay inside the Tools panel instead of attaching another sheet."
        )
        XCTAssertTrue(
            source.contains("if showingRackEditor"),
            "The rack editor should remain available as an in-panel surface."
        )
        XCTAssertTrue(
            source.contains("if let preparedAction"),
            "Prepared Tools actions should remain reviewable in-panel."
        )
    }
}
