import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class TelegramApprovalReconciliationTests: XCTestCase {
    func testResolutionEditsOriginalMessageOnceAndInvalidatesLaunch() async throws {
        let suiteName = "TelegramApprovalReconciliationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKey.remoteApprovalTelegramEnabled)
        defaults.set("42", forKey: SettingsKey.remoteApprovalTelegramChatID)
        defaults.set("42", forKey: SettingsKey.remoteApprovalTelegramUserID)
        let backend = ReconciliationSecretBackend()
        let credentials = TelegramCredentialStore(backend: backend, defaults: defaults)
        try credentials.save("123:test")
        let client = ReconciliationBotClient()
        let controller = TelegramApprovalController(
            vault: TelegramApprovalSessionVault(tokenGenerator: { "opaque-launch" }),
            credentialStore: credentials,
            botClient: client,
            defaults: defaults
        )
        let launch = try controller.prepareLaunch(
            requestID: "request-1",
            chatID: 42,
            baseURL: try XCTUnwrap(URL(string: "https://mac.tailnet:9443"))
        )
        controller.attachMessageID(314, to: launch.launch.nonce)

        controller.reconcileResolved(requestID: "request-1", decision: .approve)
        let edit = try await client.waitForEdit()

        XCTAssertEqual(edit.payload.chatID, "42")
        XCTAssertEqual(edit.payload.messageID, 314)
        XCTAssertEqual(edit.payload.text, "CodeIsland approval resolved.\nApproved once in CodeIsland.")
        XCTAssertEqual(edit.payload.replyMarkup, .empty)
        XCTAssertEqual(edit.botToken, "123:test")

        controller.reconcileResolved(requestID: "request-1", decision: .deny)
        try await Task.sleep(for: .milliseconds(50))
        let editCount = await client.editCount
        XCTAssertEqual(editCount, 1)
    }

    func testExternalResolutionUsesGenericRedactedOutcome() async throws {
        let suiteName = "TelegramApprovalReconciliationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKey.remoteApprovalTelegramEnabled)
        defaults.set("42", forKey: SettingsKey.remoteApprovalTelegramChatID)
        defaults.set("42", forKey: SettingsKey.remoteApprovalTelegramUserID)
        let backend = ReconciliationSecretBackend()
        let credentials = TelegramCredentialStore(backend: backend, defaults: defaults)
        try credentials.save("123:test")
        let client = ReconciliationBotClient()
        let controller = TelegramApprovalController(
            vault: TelegramApprovalSessionVault(tokenGenerator: { "opaque-launch" }),
            credentialStore: credentials,
            botClient: client,
            defaults: defaults
        )
        let launch = try controller.prepareLaunch(
            requestID: "request-2",
            chatID: 42,
            baseURL: try XCTUnwrap(URL(string: "https://mac.tailnet:9443"))
        )
        controller.attachMessageID(315, to: launch.launch.nonce)

        controller.reconcileResolved(requestID: "request-2", decision: nil)
        let edit = try await client.waitForEdit()

        XCTAssertEqual(edit.payload.text, "CodeIsland approval resolved.\nResolved in CodeIsland.")
        XCTAssertFalse(try XCTUnwrap(edit.payload.text).localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(try XCTUnwrap(edit.payload.text).localizedCaseInsensitiveContains("workspace"))
    }
}

private final class ReconciliationSecretBackend: TelegramSecretBackend {
    var value: String?
    func read(service _: String, account _: String) throws -> String? { value }
    func write(_ value: String, service _: String, account _: String) throws { self.value = value }
    func delete(service _: String, account _: String) throws { value = nil }
}

private actor ReconciliationBotClient: TelegramBotAPIClientProtocol {
    struct Edit {
        let payload: TelegramEditMessagePayload
        let botToken: String
    }

    private var edits: [Edit] = []
    var editCount: Int { edits.count }

    func sendMessage(
        _: TelegramSendMessagePayload,
        botToken _: String
    ) async throws -> TelegramSentMessage {
        TelegramSentMessage(messageID: 1)
    }

    func editMessage(
        _ payload: TelegramEditMessagePayload,
        botToken: String
    ) async throws {
        edits.append(Edit(payload: payload, botToken: botToken))
    }

    func waitForEdit() async throws -> Edit {
        for _ in 0..<100 {
            if let edit = edits.first { return edit }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw WaitError.timedOut
    }

    private enum WaitError: Error { case timedOut }
}
