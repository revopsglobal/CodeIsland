import XCTest
@testable import CodeIsland

final class TelegramApprovalSessionVaultTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLaunchesUseIndependentOpaqueNonces() {
        var tokens = ["launch-one", "launch-two"]
        var vault = TelegramApprovalSessionVault(tokenGenerator: { tokens.removeFirst() })

        let first = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
        let second = vault.issueLaunch(requestID: "request-2", chatID: 42, now: now)

        XCTAssertEqual(first.nonce, "launch-one")
        XCTAssertEqual(second.nonce, "launch-two")
        XCTAssertNotEqual(first.nonce, second.nonce)
    }

    func testDuplicatePendingRequestReusesUnexpiredLaunch() {
        var tokens = ["launch-one", "unused"]
        var vault = TelegramApprovalSessionVault(tokenGenerator: { tokens.removeFirst() })

        let first = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
        let duplicate = vault.issueLaunch(
            requestID: "request-1",
            chatID: 42,
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(duplicate, first)
    }

    func testSessionIsBoundToLaunchRequestAndTelegramIdentity() throws {
        var tokens = ["launch-token", "session-token"]
        var vault = TelegramApprovalSessionVault(tokenGenerator: { tokens.removeFirst() })
        let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
        let session = try vault.openSession(
            launchNonce: launch.nonce,
            telegramUserID: 42,
            expectedChatID: 42,
            now: now
        )

        XCTAssertEqual(session.requestID, "request-1")
        XCTAssertEqual(session.telegramUserID, 42)
        XCTAssertThrowsError(
            try vault.authorize(
                sessionNonce: session.nonce,
                requestID: "request-2",
                userID: 42,
                now: now
            )
        )
        XCTAssertThrowsError(
            try vault.authorize(
                sessionNonce: session.nonce,
                requestID: "request-1",
                userID: 43,
                now: now
            )
        )
    }

    func testLaunchExpiresAfterTenMinutes() {
        var vault = TelegramApprovalSessionVault(tokenGenerator: { "token" })
        let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)

        XCTAssertThrowsError(
            try vault.openSession(
                launchNonce: launch.nonce,
                telegramUserID: 42,
                expectedChatID: 42,
                now: now.addingTimeInterval(601)
            )
        )
    }

    func testSessionExpiresAfterFiveMinutes() throws {
        var tokens = ["launch-token", "session-token"]
        var vault = TelegramApprovalSessionVault(tokenGenerator: { tokens.removeFirst() })
        let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
        let session = try vault.openSession(
            launchNonce: launch.nonce,
            telegramUserID: 42,
            expectedChatID: 42,
            now: now
        )

        XCTAssertThrowsError(
            try vault.authorize(
                sessionNonce: session.nonce,
                requestID: "request-1",
                userID: 42,
                now: now.addingTimeInterval(301)
            )
        )
    }

    func testMismatchedUserAndChatAreRejected() {
        var vault = TelegramApprovalSessionVault(tokenGenerator: { "launch-token" })
        let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)

        XCTAssertThrowsError(
            try vault.openSession(
                launchNonce: launch.nonce,
                telegramUserID: 43,
                expectedChatID: 42,
                now: now
            )
        )
        XCTAssertThrowsError(
            try vault.openSession(
                launchNonce: launch.nonce,
                telegramUserID: 42,
                expectedChatID: 99,
                now: now
            )
        )
    }

    func testResolutionReturnsMessageAndInvalidatesLaunchAndSessions() throws {
        var tokens = ["launch-token", "session-token"]
        var vault = TelegramApprovalSessionVault(tokenGenerator: { tokens.removeFirst() })
        let launch = vault.issueLaunch(requestID: "request-1", chatID: 42, now: now)
        vault.attachMessageID(314, to: launch.nonce)
        let session = try vault.openSession(
            launchNonce: launch.nonce,
            telegramUserID: 42,
            expectedChatID: 42,
            now: now
        )

        let resolved = vault.resolve(requestID: "request-1")

        XCTAssertEqual(resolved?.messageID, 314)
        XCTAssertThrowsError(
            try vault.authorize(
                sessionNonce: session.nonce,
                requestID: "request-1",
                userID: 42,
                now: now
            )
        )
        XCTAssertThrowsError(
            try vault.openSession(
                launchNonce: launch.nonce,
                telegramUserID: 42,
                expectedChatID: 42,
                now: now
            )
        )
    }
}
