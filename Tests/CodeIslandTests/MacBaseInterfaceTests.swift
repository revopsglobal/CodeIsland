import Foundation
import XCTest

final class MacBaseInterfaceTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testNotchUsesSessionOnlyCodeIslandSurface() throws {
        let sourceURL = repoRoot.appendingPathComponent("Sources/CodeIsland/NotchPanelView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("GlancesToggleRow"))
        XCTAssertFalse(source.contains("GlancesView"))
        XCTAssertFalse(source.contains("PersonalHubMacView"))
        XCTAssertFalse(source.contains("MediaHUDController"))
        XCTAssertTrue(source.contains("SessionListView(appState: appState, onlySessionId: nil)"))
    }

    func testCustomMacToolViewsAreRemoved() {
        let removedPaths = [
            "Sources/CodeIsland/GlancesView.swift",
            "Sources/CodeIsland/PersonalHubMacView.swift",
            "Sources/CodeIsland/MediaHUDController.swift",
            "Sources/CodeIsland/QuickJotWindowController.swift",
        ]

        for path in removedPaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(path).path),
                "\(path) should not be part of the base Mac interface"
            )
        }
    }

    func testMediaPollingHasNoMacHUDSideEffect() throws {
        let sourceURL = repoRoot.appendingPathComponent("Sources/CodeIsland/PersonalHubDataModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("MediaHUDController"))
    }
}
