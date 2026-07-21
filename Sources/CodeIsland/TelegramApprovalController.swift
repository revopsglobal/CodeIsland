import Foundation

struct TelegramPreparedApprovalLaunch: Equatable {
    let launch: TelegramApprovalLaunch
    let reviewURL: URL
}

@MainActor
final class TelegramApprovalController {
    static let shared = TelegramApprovalController()

    private var vault: TelegramApprovalSessionVault

    init(vault: TelegramApprovalSessionVault = TelegramApprovalSessionVault()) {
        self.vault = vault
    }

    func prepareLaunch(
        requestID: String,
        chatID: Int64,
        baseURL: URL,
        now: Date = Date()
    ) throws -> TelegramPreparedApprovalLaunch {
        guard !requestID.isEmpty,
              chatID > 0,
              baseURL.scheme?.lowercased() == "https"
        else {
            throw ControllerError.unavailable
        }

        let launch = vault.issueLaunch(requestID: requestID, chatID: chatID, now: now)
        let endpoint = baseURL.appendingPathComponent("telegram/approval", isDirectory: false)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ControllerError.unavailable
        }
        components.fragment = nil
        components.queryItems = [URLQueryItem(name: "launch", value: launch.nonce)]
        guard let reviewURL = components.url else {
            throw ControllerError.unavailable
        }
        return TelegramPreparedApprovalLaunch(launch: launch, reviewURL: reviewURL)
    }

    func attachMessageID(_ messageID: Int, to launchNonce: String) {
        vault.attachMessageID(messageID, to: launchNonce)
    }

    private enum ControllerError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Secure Telegram review is unavailable"
        }
    }
}
