import Foundation
import Security

struct TelegramApprovalLaunch: Equatable {
    let nonce: String
    let requestID: String
    let chatID: Int64
    let issuedAt: Date
    let expiresAt: Date
    var messageID: Int?
}

struct TelegramApprovalSession: Equatable {
    let nonce: String
    let launchNonce: String
    let requestID: String
    let telegramUserID: Int64
    let issuedAt: Date
    let expiresAt: Date
}

struct TelegramApprovalSessionVault {
    private enum VaultError: LocalizedError {
        case invalidOrExpired

        var errorDescription: String? {
            "Telegram approval session is invalid or expired"
        }
    }

    private var launches: [String: TelegramApprovalLaunch] = [:]
    private var sessions: [String: TelegramApprovalSession] = [:]
    private let tokenGenerator: () -> String

    init(tokenGenerator: @escaping () -> String = Self.secureRandomToken) {
        self.tokenGenerator = tokenGenerator
    }

    mutating func issueLaunch(
        requestID: String,
        chatID: Int64,
        now: Date = Date()
    ) -> TelegramApprovalLaunch {
        discardExpired(now: now)
        if let existing = launches.values.first(where: {
            $0.requestID == requestID && $0.chatID == chatID
        }) {
            return existing
        }

        let nonce = freshToken(excluding: Set(launches.keys))
        let launch = TelegramApprovalLaunch(
            nonce: nonce,
            requestID: requestID,
            chatID: chatID,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(10 * 60),
            messageID: nil
        )
        launches[nonce] = launch
        return launch
    }

    mutating func attachMessageID(_ messageID: Int, to launchNonce: String) {
        guard var launch = launches[launchNonce] else { return }
        launch.messageID = messageID
        launches[launchNonce] = launch
    }

    mutating func openSession(
        launchNonce: String,
        telegramUserID: Int64,
        expectedChatID: Int64,
        now: Date = Date()
    ) throws -> TelegramApprovalSession {
        discardExpired(now: now)
        guard let launch = launches[launchNonce],
              launch.chatID == expectedChatID,
              telegramUserID == expectedChatID
        else {
            throw VaultError.invalidOrExpired
        }

        let nonce = freshToken(excluding: Set(sessions.keys))
        let session = TelegramApprovalSession(
            nonce: nonce,
            launchNonce: launchNonce,
            requestID: launch.requestID,
            telegramUserID: telegramUserID,
            issuedAt: now,
            expiresAt: min(now.addingTimeInterval(5 * 60), launch.expiresAt)
        )
        sessions[nonce] = session
        return session
    }

    mutating func authorize(
        sessionNonce: String,
        requestID: String,
        userID: Int64,
        now: Date = Date()
    ) throws -> TelegramApprovalSession {
        discardExpired(now: now)
        guard let session = sessions[sessionNonce],
              session.requestID == requestID,
              session.telegramUserID == userID
        else {
            throw VaultError.invalidOrExpired
        }
        return session
    }

    mutating func resolve(requestID: String) -> TelegramApprovalLaunch? {
        let matchingLaunches = launches.values
            .filter { $0.requestID == requestID }
            .sorted { $0.issuedAt < $1.issuedAt }
        for launch in matchingLaunches {
            launches.removeValue(forKey: launch.nonce)
        }
        for session in sessions.values where session.requestID == requestID {
            sessions.removeValue(forKey: session.nonce)
        }
        return matchingLaunches.first
    }

    mutating func discardExpired(now: Date = Date()) {
        for launch in launches.values where launch.expiresAt <= now {
            launches.removeValue(forKey: launch.nonce)
        }
        for session in sessions.values
        where session.expiresAt <= now || launches[session.launchNonce] == nil {
            sessions.removeValue(forKey: session.nonce)
        }
    }

    private func freshToken(excluding existing: Set<String>) -> String {
        for _ in 0..<4 {
            let candidate = tokenGenerator()
            if !candidate.isEmpty, !existing.contains(candidate) {
                return candidate
            }
        }
        return Self.secureRandomToken()
    }

    private static func secureRandomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return Data(bytes).telegramBase64URLEncodedString()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private extension Data {
    func telegramBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
