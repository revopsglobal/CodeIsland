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

    private init() {}

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
        sendInBackground(text: text)
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

    private func sendInBackground(text: String, reportMissingConfiguration: Bool = false) {
        guard !isSending else { return }
        guard let configuration = configuration() else {
            if reportMissingConfiguration {
                lastError = TelegramError.incompleteConfiguration.localizedDescription
            }
            return
        }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await send(text: text, configuration: configuration)
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
        case invalidResponse
        case rejected(status: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .incompleteConfiguration:
                return "Telegram needs a bot token and chat ID in CodeIsland Settings"
            case .invalidResponse:
                return "Telegram returned an invalid response"
            case .rejected(let status, let reason):
                return "Telegram rejected the alert (\(status)): \(reason)"
            }
        }
    }

    private func configuration() -> Configuration? {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: SettingsKey.remoteApprovalTelegramEnabled) == nil
            ? SettingsDefaults.remoteApprovalTelegramEnabled
            : defaults.bool(forKey: SettingsKey.remoteApprovalTelegramEnabled)
        let botToken = (defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken)
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

    private func send(text: String, configuration: Configuration) async throws {
        guard let url = URL(string: "https://api.telegram.org/bot\(configuration.botToken)/sendMessage") else {
            throw TelegramError.incompleteConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "chat_id": configuration.chatID,
                "disable_web_page_preview": true,
                "text": text
            ],
            options: [.sortedKeys]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TelegramError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = object?["description"] as? String
                ?? object?["error"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "unknown"
            throw TelegramError.rejected(status: http.statusCode, reason: reason)
        }
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
