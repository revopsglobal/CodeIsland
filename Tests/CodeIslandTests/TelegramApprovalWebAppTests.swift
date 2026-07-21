import XCTest
@testable import CodeIsland

final class TelegramApprovalWebAppTests: XCTestCase {
    func testShellUsesTelegramSignedDataAndPostOnlyActions() {
        let html = TelegramApprovalWebApp.html

        XCTAssertTrue(html.contains("telegram-web-app.js"))
        XCTAssertTrue(html.contains("Telegram.WebApp.initData"))
        XCTAssertFalse(html.contains("initDataUnsafe"))
        XCTAssertTrue(html.contains("method: 'POST'"))
        XCTAssertTrue(html.contains("/api/telegram/session"))
        XCTAssertTrue(html.contains("/api/telegram/approvals/"))
        XCTAssertFalse(html.contains("method: 'GET'"))
    }

    func testShellIsSummaryFirstAndIncludesExplicitDecisionControls() {
        let html = TelegramApprovalWebApp.html

        for id in ["summary", "risk", "scope", "details", "deny", "approve", "fingerprint"] {
            XCTAssertTrue(html.contains("id=\"\(id)\""), "Missing \(id)")
        }
        XCTAssertTrue(html.contains("Show exact details"))
        XCTAssertTrue(html.contains("Approve once"))
        XCTAssertTrue(html.contains("Deny"))
    }

    func testShellHasNativeAccessibilityAndPrivacyContract() {
        let html = TelegramApprovalWebApp.html

        XCTAssertTrue(html.contains("safe-area-inset-top"))
        XCTAssertTrue(html.contains("--tg-theme-bg-color"))
        XCTAssertTrue(html.contains(":focus-visible"))
        XCTAssertTrue(html.contains("min-height: 44px"))
        XCTAssertTrue(html.contains("prefers-reduced-motion"))
        XCTAssertTrue(html.contains("textContent"))
        XCTAssertFalse(html.contains("innerHTML"))
        XCTAssertFalse(html.contains("localStorage"))
        XCTAssertFalse(html.contains("serviceWorker"))
        XCTAssertFalse(html.localizedCaseInsensitiveContains("analytics"))
        XCTAssertFalse(html.contains("fonts.googleapis"))
    }
}
