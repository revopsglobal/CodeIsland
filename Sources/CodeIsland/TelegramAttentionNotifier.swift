import CodeIslandCore
import Foundation
import os.log

@MainActor
final class TelegramAttentionNotifier: ObservableObject {
    static let shared = TelegramAttentionNotifier()
    private static let buddyTestFlightURL = URL(string: "itms-beta://")

    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSending = false

    private let log = Logger(subsystem: "com.codeisland", category: "telegram")
    private let credentialStore: TelegramCredentialStore
    private let botClient: any TelegramBotAPIClientProtocol
    private let approvalController: TelegramApprovalController
    private var activeSendCount = 0
    private var pendingApprovalDeliveries = Set<String>()

    init(
        credentialStore: TelegramCredentialStore = TelegramCredentialStore(),
        botClient: any TelegramBotAPIClientProtocol = TelegramBotAPIClient(),
        approvalController: TelegramApprovalController? = nil
    ) {
        self.credentialStore = credentialStore
        self.botClient = botClient
        self.approvalController = approvalController ?? .shared
    }

    func notify(envelope: RemoteAttentionPushEnvelope) {
        guard envelope.state == .pending
                || (envelope.kind == .task && envelope.taskState == .failed)
        else { return }

        let remoteURL = Self.remoteApprovalURL()
        let text = TelegramAttentionMessageBuilder.message(
            for: envelope,
            remoteURL: remoteURL,
            buddyURL: Self.buddyURL(for: envelope),
            testFlightURL: Self.buddyTestFlightURL,
            expectedBuddyBuild: Self.expectedBuddyBuild()
        )
        sendInBackground(text: text, envelope: envelope, remoteURL: remoteURL)
    }

    func sendTestAlert() {
        let text = TelegramAttentionMessageBuilder.testMessage(
            remoteURL: Self.remoteApprovalURL(),
            buddyURL: PersonalHubDeepLink.pendingQuestion(id: nil).url,
            testFlightURL: Self.buddyTestFlightURL,
            expectedBuddyBuild: Self.expectedBuddyBuild()
        )
        sendInBackground(text: text, reportMissingConfiguration: true)
    }

    private func sendInBackground(
        text: String,
        envelope: RemoteAttentionPushEnvelope? = nil,
        remoteURL: URL? = nil,
        reportMissingConfiguration: Bool = false
    ) {
        let resolvedConfiguration: Configuration
        do {
            guard let configured = try configuration() else {
                if reportMissingConfiguration {
                    lastError = TelegramError.incompleteConfiguration.localizedDescription
                }
                return
            }
            resolvedConfiguration = configured
        } catch {
            lastError = TelegramError.credentialUnavailable.localizedDescription
            log.error("telegram credentials are unavailable")
            return
        }

        var preparedLaunch: TelegramPreparedApprovalLaunch?
        if let envelope,
           envelope.kind == .approval,
           envelope.state == .pending,
           let remoteURL,
           let chatID = Int64(resolvedConfiguration.chatID),
           chatID > 0 {
            guard !pendingApprovalDeliveries.contains(envelope.requestID) else { return }
            do {
                let prepared = try approvalController.prepareLaunch(
                    requestID: envelope.requestID,
                    chatID: chatID,
                    baseURL: remoteURL
                )
                guard prepared.launch.messageID == nil else { return }
                pendingApprovalDeliveries.insert(envelope.requestID)
                preparedLaunch = prepared
            } catch {
                log.error("secure Telegram review launch is unavailable")
            }
        }

        let payload = preparedLaunch.map {
            TelegramSendMessagePayload.secureReview(
                chatID: resolvedConfiguration.chatID,
                text: text,
                reviewURL: $0.reviewURL
            )
        } ?? TelegramSendMessagePayload.redactedAlert(
            chatID: resolvedConfiguration.chatID,
            text: text
        )

        activeSendCount += 1
        isSending = true
        Task {
            defer {
                activeSendCount = max(0, activeSendCount - 1)
                isSending = activeSendCount > 0
                if let requestID = envelope?.requestID {
                    pendingApprovalDeliveries.remove(requestID)
                }
            }
            do {
                let message = try await botClient.sendMessage(
                    payload,
                    botToken: resolvedConfiguration.botToken
                )
                if let preparedLaunch {
                    approvalController.attachMessageID(
                        message.messageID,
                        to: preparedLaunch.launch.nonce
                    )
                }
                lastDeliveryAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                log.error("telegram delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct Configuration {
        let botToken: String
        let chatID: String
    }

    private enum TelegramError: LocalizedError {
        case incompleteConfiguration
        case credentialUnavailable

        var errorDescription: String? {
            switch self {
            case .incompleteConfiguration:
                return "Telegram needs a bot token and chat ID in CodeIsland Settings"
            case .credentialUnavailable:
                return "Telegram could not access its saved bot credential"
            }
        }
    }

    private func configuration() throws -> Configuration? {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: SettingsKey.remoteApprovalTelegramEnabled) == nil
            ? SettingsDefaults.remoteApprovalTelegramEnabled
            : defaults.bool(forKey: SettingsKey.remoteApprovalTelegramEnabled)
        let botToken = try (credentialStore.loadMigratingLegacyValue()
            ?? SettingsDefaults.remoteApprovalTelegramBotToken).trimmingCharacters(in: .whitespacesAndNewlines)
        let chatID = (defaults.string(forKey: SettingsKey.remoteApprovalTelegramChatID)
            ?? SettingsDefaults.remoteApprovalTelegramChatID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !botToken.isEmpty, !chatID.isEmpty else { return nil }
        return Configuration(botToken: botToken, chatID: chatID)
    }

    private static func remoteApprovalURL() -> URL? {
        let raw = (UserDefaults.standard.string(forKey: SettingsKey.remoteApprovalTailnetURL)
            ?? SettingsDefaults.remoteApprovalTailnetURL).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https"
        else {
            return nil
        }
        return url
    }

    private static func buddyURL(for envelope: RemoteAttentionPushEnvelope) -> URL {
        switch envelope.kind {
        case .approval:
            return PersonalHubDeepLink.pendingApproval(id: nil).url
        case .question:
            return PersonalHubDeepLink.pendingQuestion(id: nil).url
        case .task:
            return UUID(uuidString: envelope.requestID)
                .map { PersonalHubDeepLink.task(id: $0).url }
                ?? PersonalHubDeepLink.needsYou.url
        }
    }

    private static func expectedBuddyBuild() -> String? {
        let defaults = UserDefaults.standard
        let version = (defaults.string(forKey: SettingsKey.remoteApprovalExpectedClientVersion)
            ?? SettingsDefaults.remoteApprovalExpectedClientVersion).trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (defaults.string(forKey: SettingsKey.remoteApprovalExpectedClientBuild)
            ?? SettingsDefaults.remoteApprovalExpectedClientBuild).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty || !build.isEmpty else { return nil }
        guard !version.isEmpty else { return build }
        guard !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

}

enum TelegramAttentionMessageBuilder {
    static func testMessage(
        remoteURL: URL?,
        buddyURL: URL? = nil,
        testFlightURL: URL? = nil,
        expectedBuddyBuild: String? = nil
    ) -> String {
        let now = Date()
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "telegram-test-\(UUID().uuidString)",
            kind: .question,
            state: .pending,
            requestID: "telegram-test",
            issuedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )
        return message(
            for: envelope,
            remoteURL: remoteURL,
            buddyURL: buddyURL,
            testFlightURL: testFlightURL,
            expectedBuddyBuild: expectedBuddyBuild
        )
    }

    static func message(
        for envelope: RemoteAttentionPushEnvelope,
        remoteURL: URL?,
        buddyURL: URL? = nil,
        testFlightURL: URL? = nil,
        expectedBuddyBuild: String? = nil
    ) -> String {
        let headline: String
        switch envelope.kind {
        case .approval: headline = "CodeIsland needs your approval."
        case .question: headline = "CodeIsland needs your answer."
        case .task:
            headline = envelope.taskState == .failed
                ? "A CodeIsland coding task failed."
                : "A CodeIsland coding task needs you."
        }
        var lines = [
            headline,
            "Open Buddy to review the private details."
        ]
        if let buddyURL {
            lines.append("Buddy: \(buddyURL.absoluteString)")
        }
        if let remoteURL {
            lines.append("Web fallback: \(remoteURL.absoluteString)")
        }
        if let testFlightURL {
            let trimmedBuild = expectedBuddyBuild?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let target = trimmedBuild.isEmpty ? "" : " to \(trimmedBuild)"
            lines.append("If Buddy is stale: update CodeIsland Buddy\(target) in TestFlight \(testFlightURL.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }
}
