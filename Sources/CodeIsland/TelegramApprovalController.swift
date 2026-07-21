import CodeIslandCore
import Foundation
import os.log

struct TelegramPreparedApprovalLaunch: Equatable {
    let launch: TelegramApprovalLaunch
    let reviewURL: URL
}

struct TelegramSessionRequest: Codable, Equatable {
    let initData: String
    let launchNonce: String
}

struct TelegramDecisionRouteRequest: Codable, Equatable {
    let initData: String
    let launchNonce: String
    let sessionNonce: String
    let actionToken: String
    let decision: RemoteApprovalDecision
}

struct TelegramApprovalSessionResponse: Codable, Equatable {
    let sessionNonce: String
    let requestID: String
    let headline: String
    let summary: String
    let agent: String
    let workspace: String?
    let risk: CommandRisk
    let riskReason: String
    let changedScope: [String]
    let details: [TelegramApprovalDetail]
    let fingerprint: String
    let createdAt: Date
    let actionToken: String
    let actionExpiresAt: Date
}

struct TelegramDecisionRouteResponse: Codable, Equatable {
    let resolved: Bool
    let requestID: String
    let decision: RemoteApprovalDecision
    let message: String
}

struct TelegramApprovalRouteError: Error, Equatable {
    let status: Int
    let message: String

    static let badRequest = Self(status: 400, message: "Secure approval request is invalid")
    static let forbidden = Self(status: 403, message: "Telegram authorization could not be verified")
    static let notFound = Self(status: 404, message: "Secure approval link is invalid or expired")
    static let conflict = Self(status: 409, message: "Approval is no longer pending")
    static let unavailable = Self(status: 503, message: "Secure Telegram review is unavailable")
}

@MainActor
final class TelegramApprovalController {
    static let shared = TelegramApprovalController()

    private let log = Logger(subsystem: "com.codeisland", category: "telegram-approval")
    private var vault: TelegramApprovalSessionVault
    private let credentialStore: TelegramCredentialStore
    private let botClient: any TelegramBotAPIClientProtocol
    private let defaults: UserDefaults

    init(
        vault: TelegramApprovalSessionVault = TelegramApprovalSessionVault(),
        credentialStore: TelegramCredentialStore? = nil,
        botClient: any TelegramBotAPIClientProtocol = TelegramBotAPIClient(),
        defaults: UserDefaults = .standard
    ) {
        self.vault = vault
        self.defaults = defaults
        self.credentialStore = credentialStore ?? TelegramCredentialStore(defaults: defaults)
        self.botClient = botClient
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
            throw TelegramApprovalRouteError.unavailable
        }

        let launch = vault.issueLaunch(requestID: requestID, chatID: chatID, now: now)
        let endpoint = baseURL.appendingPathComponent("telegram/approval", isDirectory: false)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TelegramApprovalRouteError.unavailable
        }
        components.fragment = nil
        components.queryItems = [URLQueryItem(name: "launch", value: launch.nonce)]
        guard let reviewURL = components.url else {
            throw TelegramApprovalRouteError.unavailable
        }
        return TelegramPreparedApprovalLaunch(launch: launch, reviewURL: reviewURL)
    }

    func attachMessageID(_ messageID: Int, to launchNonce: String) {
        vault.attachMessageID(messageID, to: launchNonce)
    }

    func createSession(
        _ request: TelegramSessionRequest,
        appState: AppState,
        coordinator: RemoteApprovalCoordinator,
        now: Date = Date()
    ) throws -> TelegramApprovalSessionResponse {
        let configuration = try privateConfiguration()
        let identity: TelegramIdentity
        do {
            identity = try TelegramInitDataValidator(botToken: configuration.botToken).validate(
                request.initData,
                allowedUserID: configuration.userID,
                now: now
            )
        } catch {
            throw TelegramApprovalRouteError.forbidden
        }

        let session: TelegramApprovalSession
        do {
            session = try vault.openSession(
                launchNonce: request.launchNonce,
                telegramUserID: identity.userID,
                expectedChatID: configuration.chatID,
                now: now
            )
        } catch {
            throw TelegramApprovalRouteError.notFound
        }

        let deviceID = telegramDeviceID(userID: identity.userID)
        let snapshot = coordinator.snapshot(appState: appState, deviceID: deviceID)
        guard let approval = snapshot.approvals.first(where: { $0.id == session.requestID }),
              let pending = appState.permissionQueue.first(where: { $0.id == session.requestID })
        else {
            _ = vault.resolve(requestID: session.requestID)
            throw TelegramApprovalRouteError.conflict
        }
        let presentation = TelegramApprovalPresentationBuilder.build(
            request: pending,
            approval: approval
        )
        return TelegramApprovalSessionResponse(
            sessionNonce: session.nonce,
            requestID: presentation.requestID,
            headline: presentation.headline,
            summary: presentation.summary,
            agent: presentation.agent,
            workspace: presentation.workspace,
            risk: presentation.risk,
            riskReason: presentation.riskReason,
            changedScope: presentation.changedScope,
            details: presentation.details,
            fingerprint: presentation.fingerprint,
            createdAt: presentation.createdAt,
            actionToken: presentation.actionToken,
            actionExpiresAt: presentation.actionExpiresAt
        )
    }

    func decide(
        _ request: TelegramDecisionRouteRequest,
        requestID: String,
        appState: AppState,
        coordinator: RemoteApprovalCoordinator,
        now: Date = Date()
    ) throws -> TelegramDecisionRouteResponse {
        guard !requestID.isEmpty,
              !request.actionToken.isEmpty,
              !request.sessionNonce.isEmpty,
              !request.launchNonce.isEmpty
        else {
            throw TelegramApprovalRouteError.badRequest
        }
        let configuration = try privateConfiguration()
        let session: TelegramApprovalSession
        do {
            session = try vault.authorize(
                sessionNonce: request.sessionNonce,
                requestID: requestID,
                userID: configuration.userID,
                now: now
            )
        } catch {
            throw TelegramApprovalRouteError.forbidden
        }
        guard session.launchNonce == request.launchNonce else {
            throw TelegramApprovalRouteError.forbidden
        }

        // Telegram supplies one signed initData value for the lifetime of a Mini App.
        // Session creation proved it fresh; revalidate the same signature against that
        // issuance time while the shorter, single-use CodeIsland session is still valid.
        do {
            _ = try TelegramInitDataValidator(botToken: configuration.botToken).validate(
                request.initData,
                allowedUserID: configuration.userID,
                now: session.issuedAt
            )
        } catch {
            throw TelegramApprovalRouteError.forbidden
        }

        let result = coordinator.resolve(
            appState: appState,
            requestID: requestID,
            actionToken: request.actionToken,
            deviceID: telegramDeviceID(userID: configuration.userID),
            deviceName: "Telegram",
            decision: request.decision
        )
        switch result {
        case .resolved:
            reconcileResolved(requestID: requestID, decision: request.decision)
            return TelegramDecisionRouteResponse(
                resolved: true,
                requestID: requestID,
                decision: request.decision,
                message: request.decision == .approve
                    ? "Approved once on your Mac."
                    : "Denied on your Mac."
            )
        case .expired:
            throw TelegramApprovalRouteError.conflict
        case .stale:
            reconcileResolved(requestID: requestID, decision: nil)
            throw TelegramApprovalRouteError.conflict
        case .unauthorized:
            throw TelegramApprovalRouteError.forbidden
        case .invalid:
            throw TelegramApprovalRouteError.badRequest
        }
    }

    /// Invalidates all launch/session material immediately, then edits the one
    /// original Telegram alert in place. The edit contains no private request
    /// data and removes the button, so old notifications cannot look actionable.
    func reconcileResolved(
        requestID: String,
        decision: RemoteApprovalDecision?
    ) {
        guard let launch = vault.resolve(requestID: requestID),
              let messageID = launch.messageID,
              let configuration = try? privateConfiguration(),
              launch.chatID == configuration.chatID
        else { return }

        let outcome: String
        switch decision {
        case .approve: outcome = "Approved once in CodeIsland."
        case .deny: outcome = "Denied in CodeIsland."
        case nil: outcome = "Resolved in CodeIsland."
        }
        let payload = TelegramEditMessagePayload(
            chatID: String(configuration.chatID),
            messageID: messageID,
            text: "CodeIsland approval resolved.\n\(outcome)",
            replyMarkup: .empty
        )
        let botToken = configuration.botToken
        Task {
            do {
                try await botClient.editMessage(payload, botToken: botToken)
            } catch {
                log.error("telegram resolution edit failed")
            }
        }
    }

    private func privateConfiguration() throws -> (
        botToken: String,
        chatID: Int64,
        userID: Int64
    ) {
        let enabled = defaults.object(forKey: SettingsKey.remoteApprovalTelegramEnabled) == nil
            ? SettingsDefaults.remoteApprovalTelegramEnabled
            : defaults.bool(forKey: SettingsKey.remoteApprovalTelegramEnabled)
        guard enabled,
              let botToken = try? credentialStore.loadMigratingLegacyValue(),
              !botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chatID = Int64((defaults.string(forKey: SettingsKey.remoteApprovalTelegramChatID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              let userID = Int64((defaults.string(forKey: SettingsKey.remoteApprovalTelegramUserID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              chatID > 0,
              userID > 0,
              chatID == userID
        else {
            throw TelegramApprovalRouteError.unavailable
        }
        return (botToken, chatID, userID)
    }

    private func telegramDeviceID(userID: Int64) -> String {
        "telegram:\(userID)"
    }
}
