import XCTest
@testable import CodeIsland

final class RemoteApprovalWebAppTests: XCTestCase {
    func testCodingTaskWebParityIncludesReviewedLifecycleActions() {
        let html = RemoteApprovalWebApp.html
        XCTAssertTrue(html.contains(#"id="taskComposer""#))
        XCTAssertTrue(html.contains("Coding tasks · edit &amp; test"))
        XCTAssertTrue(html.contains("fetch('/api/tasks/workspaces'"))
        XCTAssertTrue(html.contains("fetch('/api/tasks'"))
        XCTAssertTrue(html.contains("/follow-up`"))
        XCTAssertTrue(html.contains("/cancel`"))
        XCTAssertTrue(html.contains("Dispatch this exact task?"))
        XCTAssertTrue(html.contains("Stop this exact coding task?"))
        XCTAssertTrue(html.contains("Completion evidence"))
        XCTAssertFalse(html.contains("window.confirm"))
        XCTAssertFalse(html.contains("window.prompt"))
    }

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
        XCTAssertTrue(html.contains("!reviewDialog.classList.contains('hidden')"))
    }

    func testWebFallbackUsesInlineReviewSheetsInsteadOfBrowserDialogs() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains(#"id="reviewDialog""#))
        XCTAssertTrue(html.contains("function reviewSheet"))
        XCTAssertTrue(html.contains("function confirmSheet"))
        XCTAssertTrue(html.contains("function promptSheet"))
        XCTAssertFalse(html.contains("prompt("))
        XCTAssertFalse(html.contains("confirm("))
        XCTAssertFalse(html.contains("alert("))
    }

    func testClaudeAskResponseBodyRendersInWebFallback() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains(".hub-item-detail"))
        XCTAssertTrue(html.contains("moduleID==='claude'&&item.detail"))
        XCTAssertTrue(html.contains("${visibleDetail}"))
    }

    func testActionMetadataUsesAttributeEscaping() {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains("function escapeAttribute(value='')"))
        XCTAssertTrue(html.contains(#"data-value="${escapeAttribute(action.value||'')}""#))
        XCTAssertTrue(html.contains(#"data-token="${escapeAttribute(item.actionToken)}""#))
        XCTAssertTrue(html.contains(#"value="${escapeAttribute(option)}""#))
        XCTAssertFalse(html.contains(#"data-value="${escapeHTML(action.value||'')}""#))
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

    func testWebFallbackRoutesReadOnlyRefreshWithoutMacActionConfirmation() throws {
        let html = RemoteApprovalWebApp.html

        XCTAssertTrue(html.contains("const readOnlyHubActions=new Set(['system.refresh','weather.refresh','agents.refresh','github.refresh','battery.refresh'])"))
        XCTAssertTrue(html.contains("function isReadOnlyHubAction(moduleID,actionID)"))
        XCTAssertTrue(html.contains("if(isReadOnlyHubAction(moduleID,actionID))"))
        XCTAssertTrue(html.contains("notify(`Refreshed ${moduleNames[moduleID]||moduleID}`)"))

        let readOnlyBranch = try XCTUnwrap(html.range(of: "if(isReadOnlyHubAction(moduleID,actionID))"))
        let prepareFetch = try XCTUnwrap(html.range(of: "fetch('/api/hub/actions/prepare'"))
        XCTAssertLessThan(
            readOnlyBranch.lowerBound,
            prepareFetch.lowerBound,
            "Read-only refresh must return before the web fallback prepares a mutation confirmation"
        )
    }
}
