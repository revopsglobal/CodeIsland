import XCTest
@testable import CodeIsland

final class RemoteApprovalWebAppTests: XCTestCase {
    func testAttentionRequestsRenderBeforePersonalTools() throws {
        let html = RemoteApprovalWebApp.html
        let questions = try XCTUnwrap(html.range(of: #"<section id="questions">"#))
        let approvals = try XCTUnwrap(html.range(of: #"<section id="approvals">"#))
        let tools = try XCTUnwrap(html.range(of: #"<section id="hub" class="module-grid">"#))

        XCTAssertLessThan(questions.lowerBound, tools.lowerBound)
        XCTAssertLessThan(approvals.lowerBound, tools.lowerBound)
        XCTAssertTrue(html.contains("Now · agent questions"))
        XCTAssertTrue(html.contains("Now · agent approvals"))
        XCTAssertTrue(html.contains("Today &amp; tools"))
    }

    func testMobileWebFallbackHasAccessibleFeedbackAndTargets() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains(#"role="status" aria-live="polite""#))
        XCTAssertTrue(html.contains("min-height:44px"))
        XCTAssertTrue(html.contains("button:focus-visible"))
        XCTAssertTrue(html.contains("notify(error.message,true)"))
        XCTAssertFalse(html.contains("alert("))
    }

    func testPollingDoesNotReplaceActiveInput() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains("function userIsEditing()"))
        XCTAssertTrue(html.contains("!userIsEditing())refresh()"))
        XCTAssertTrue(html.contains("mediaSeekState.active"))
        XCTAssertTrue(html.contains("claudeInput.resolve"))
    }

    func testClaudeAskResponseBodyRendersInWebFallback() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains(".hub-item-detail"))
        XCTAssertTrue(html.contains("moduleID==='claude'&&item.detail"))
        XCTAssertTrue(html.contains("${visibleDetail}"))
    }

    func testFallbackBrandMatchesNativeApp() {
        XCTAssertTrue(RemoteApprovalWebApp.html.contains("<title>CodeIsland</title>"))
        XCTAssertTrue(RemoteApprovalWebApp.html.contains("Your Mac, when it needs you"))
        XCTAssertTrue(RemoteApprovalWebApp.manifest.contains(#""name": "CodeIsland""#))
        XCTAssertTrue(RemoteApprovalWebApp.manifest.contains(#""short_name": "CodeIsland""#))
        XCTAssertTrue(RemoteApprovalWebApp.manifest.contains(#""src": "/app-icon.svg""#))
        XCTAssertTrue(RemoteApprovalWebApp.manifest.contains(#""purpose": "any maskable""#))
        XCTAssertTrue(RemoteApprovalWebApp.html.contains(#"<link rel="icon" href="/app-icon.svg""#))
        XCTAssertTrue(RemoteApprovalWebApp.iconSVG.contains(#"viewBox="0 0 1024 1024""#))
    }
}
