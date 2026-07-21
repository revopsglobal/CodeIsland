import Foundation

struct TelegramApprovalReadiness: Equatable {
    let isReady: Bool
    let issues: [String]

    init(
        enabled: Bool,
        credentialStored: Bool,
        chatID: String,
        userID: String,
        tailnetURL: String,
        serviceRunning: Bool
    ) {
        var issues: [String] = []
        if !enabled { issues.append("Turn on Telegram escalation alerts") }
        if !credentialStored { issues.append("Save the bot token in Keychain") }

        let normalizedChatID = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let privateChatID = Int64(normalizedChatID)
        let allowlistedUserID = Int64(normalizedUserID)
        if privateChatID == nil || privateChatID ?? 0 <= 0 {
            issues.append("Enter your positive private Chat ID")
        }
        if allowlistedUserID == nil || allowlistedUserID ?? 0 <= 0 {
            issues.append("Enter your positive Telegram User ID")
        }
        if let privateChatID, let allowlistedUserID,
           privateChatID != allowlistedUserID {
            issues.append("Use the same ID for your private chat and allowlisted user")
        }

        let trimmedURL = tailnetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if URL(string: trimmedURL)?.scheme?.lowercased() != "https" {
            issues.append("Start a private Tailscale HTTPS endpoint")
        }
        if !serviceRunning { issues.append("Start the remote approval service") }

        self.issues = issues
        isReady = issues.isEmpty
    }
}
