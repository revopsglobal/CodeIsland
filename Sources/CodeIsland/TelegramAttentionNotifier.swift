import CodeIslandCore
import Foundation
import os.log

@MainActor
final class TelegramAttentionNotifier: ObservableObject {
    static let shared = TelegramAttentionNotifier()

    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSending = false

    private let log = Logger(subsystem: "com.codeisland", category: "telegram")

    private init() {}

    func notify(envelope: RemoteAttentionPushEnvelope) {
        guard envelope.state == .pending else { return }

        let remoteURL = Self.remoteApprovalURL()
        let text = TelegramAttentionMessageBuilder.message(
            for: envelope,
            remoteURL: remoteURL
        )
        sendInBackground(text: text)
    }

    func sendTestAlert() {
        let text = TelegramAttentionMessageBuilder.testMessage(remoteURL: Self.remoteApprovalURL())
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
    static func testMessage(remoteURL: URL?) -> String {
        let now = Date()
        let envelope = RemoteAttentionPushEnvelope(
            eventID: "telegram-test-\(UUID().uuidString)",
            kind: .question,
            state: .pending,
            requestID: "telegram-test",
            issuedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )
        return message(for: envelope, remoteURL: remoteURL)
    }

    static func message(
        for envelope: RemoteAttentionPushEnvelope,
        remoteURL: URL?
    ) -> String {
        let noun = envelope.kind == .approval ? "approval" : "answer"
        var lines = [
            "CodeIsland needs your \(noun).",
            "Open Buddy to review the private details."
        ]
        if let remoteURL {
            lines.append(remoteURL.absoluteString)
        }
        return lines.joined(separator: "\n")
    }
}
