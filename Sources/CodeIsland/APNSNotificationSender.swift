import Combine
import CodeIslandCore
import CryptoKit
import Foundation
import os.log

@MainActor
final class APNSNotificationSender: ObservableObject {
    static let shared = APNSNotificationSender()

    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.codeisland", category: "apns")
    private var cachedJWT: (value: String, createdAt: Date, keyID: String, teamID: String)?

    private init() {}

    func notify(
        requestID: String,
        kind: RemoteAttentionKind,
        state: RemoteAttentionState,
        devices: [RemoteApprovalDevice]
    ) {
        precondition(kind != .task, "Use notifyTask for task lifecycle events")
        let issuedAt = Date()
        deliver(
            envelope: RemoteAttentionPushEnvelope(
                kind: kind,
                state: state,
                requestID: requestID,
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(state == .pending ? 600 : 60)
            ),
            devices: devices
        )
    }

    func notifyTask(
        taskID: UUID,
        state: RemoteTaskState,
        devices: [RemoteApprovalDevice]
    ) {
        let key = taskID.uuidString.lowercased()
        let targets = devices.filter { device in
            let followed = device.liveActivityUpdateTokens?[key]?.isEmpty == false
            return RemoteTaskAttentionPolicy.shouldNotifyImmediately(state: state, isFollowed: followed)
        }
        guard !targets.isEmpty else { return }
        let issuedAt = Date()
        deliver(
            envelope: RemoteAttentionPushEnvelope(
                kind: .task,
                state: state.isTerminal ? .resolved : .pending,
                requestID: key,
                taskState: state,
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(state.isTerminal ? 300 : 600)
            ),
            devices: targets
        )
    }

    private func deliver(
        envelope: RemoteAttentionPushEnvelope,
        devices: [RemoteApprovalDevice]
    ) {
        let requestID = envelope.requestID
        let state = envelope.state
        let targets = devices.filter { device in
            device.pushToken?.isEmpty == false
                || (APNSNotificationPayloadBuilder.shouldPushToStart(envelope)
                    && device.liveActivityPushToStartToken?.isEmpty == false)
                || (state != .pending && device.liveActivityUpdateTokens?[requestID]?.isEmpty == false)
        }
        guard !targets.isEmpty else { return }
        guard let configuration = configuration() else { return }
        Task {
            do {
                let jwt = try authorizationToken(configuration: configuration)
                for device in targets {
                    let environment = device.pushEnvironment ?? "production"
                    let pushToken = device.pushToken.flatMap { $0.isEmpty ? nil : $0 }
                    let pushToStartToken = device.liveActivityPushToStartToken.flatMap { $0.isEmpty ? nil : $0 }
                    let updateToken = device.liveActivityUpdateTokens?[requestID].flatMap { $0.isEmpty ? nil : $0 }

                    if envelope.kind == .task, let token = updateToken {
                        if APNSNotificationPayloadBuilder.isVisibleAlert(envelope), let pushToken {
                            try await send(
                                envelope: envelope,
                                token: pushToken,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt
                            )
                        }
                        let terminal = envelope.taskState?.isTerminal == true
                        try await sendLiveActivity(
                            payload: terminal
                                ? APNSNotificationPayloadBuilder.liveActivityEndData(for: envelope)
                                : APNSNotificationPayloadBuilder.liveActivityUpdateData(for: envelope),
                            token: token,
                            environment: environment,
                            configuration: configuration,
                            jwt: jwt,
                            priority: terminal ? "5" : "10",
                            expiration: envelope.expiresAt
                        )
                        continue
                    }

                    if APNSNotificationPayloadBuilder.shouldPushToStart(envelope), let token = pushToStartToken {
                        do {
                            try await sendLiveActivity(
                                payload: APNSNotificationPayloadBuilder.liveActivityStartData(for: envelope),
                                token: token,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt,
                                priority: "10",
                                expiration: envelope.expiresAt
                            )
                        } catch {
                            guard let fallbackToken = pushToken else { throw error }
                            log.warning("Live Activity start failed; using the private notification fallback")
                            try await send(
                                envelope: envelope,
                                token: fallbackToken,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt
                            )
                        }
                    } else if APNSNotificationPayloadBuilder.usesVisibleNotificationFallback(
                        for: envelope,
                        hasPushToStartToken: false
                    ) {
                        if let token = pushToken {
                            try await send(
                                envelope: envelope,
                                token: token,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt
                            )
                        }
                    } else {
                        if let token = pushToken {
                            try await send(
                                envelope: envelope,
                                token: token,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt
                            )
                        }
                        if let token = updateToken {
                            try await sendLiveActivity(
                                payload: APNSNotificationPayloadBuilder.liveActivityEndData(for: envelope),
                                token: token,
                                environment: environment,
                                configuration: configuration,
                                jwt: jwt,
                                priority: "5",
                                expiration: envelope.expiresAt
                            )
                        }
                    }
                }
                lastDeliveryAt = Date()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
                log.error("push delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private struct Configuration {
        let teamID: String
        let keyID: String
        let topic: String
        let privateKey: P256.Signing.PrivateKey
    }

    private enum PushError: LocalizedError {
        case incompleteConfiguration
        case invalidResponse
        case rejected(status: Int, reason: String)

        var errorDescription: String? {
            switch self {
            case .incompleteConfiguration:
                return "APNs needs a team ID, key ID, topic, and .p8 private key in CodeIsland Settings"
            case .invalidResponse:
                return "APNs returned an invalid response"
            case .rejected(let status, let reason):
                return "APNs rejected the notification (\(status)): \(reason)"
            }
        }
    }

    private func configuration() -> Configuration? {
        let defaults = UserDefaults.standard
        let teamID = (defaults.string(forKey: SettingsKey.remoteApprovalAPNSTeamID)
            ?? SettingsDefaults.remoteApprovalAPNSTeamID).trimmingCharacters(in: .whitespacesAndNewlines)
        let keyID = (defaults.string(forKey: SettingsKey.remoteApprovalAPNSKeyID)
            ?? SettingsDefaults.remoteApprovalAPNSKeyID).trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = (defaults.string(forKey: SettingsKey.remoteApprovalAPNSTopic)
            ?? SettingsDefaults.remoteApprovalAPNSTopic).trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (defaults.string(forKey: SettingsKey.remoteApprovalAPNSPrivateKeyPath)
            ?? SettingsDefaults.remoteApprovalAPNSPrivateKeyPath).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !teamID.isEmpty, !keyID.isEmpty, !topic.isEmpty, !path.isEmpty,
              let pem = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8),
              let privateKey = try? P256.Signing.PrivateKey(pemRepresentation: pem)
        else {
            return nil
        }
        return Configuration(teamID: teamID, keyID: keyID, topic: topic, privateKey: privateKey)
    }

    private func authorizationToken(configuration: Configuration) throws -> String {
        if let cachedJWT,
           cachedJWT.keyID == configuration.keyID,
           cachedJWT.teamID == configuration.teamID,
           Date().timeIntervalSince(cachedJWT.createdAt) < 45 * 60 {
            return cachedJWT.value
        }

        let header = try JSONSerialization.data(withJSONObject: [
            "alg": "ES256",
            "kid": configuration.keyID
        ], options: [.sortedKeys])
        let claims = try JSONSerialization.data(withJSONObject: [
            "iss": configuration.teamID,
            "iat": Int(Date().timeIntervalSince1970)
        ], options: [.sortedKeys])
        let unsigned = "\(header.base64URLEncodedString()).\(claims.base64URLEncodedString())"
        let signature = try configuration.privateKey.signature(for: Data(unsigned.utf8))
        let jwt = "\(unsigned).\(signature.rawRepresentation.base64URLEncodedString())"
        cachedJWT = (jwt, Date(), configuration.keyID, configuration.teamID)
        return jwt
    }

    private func send(
        envelope: RemoteAttentionPushEnvelope,
        token: String,
        environment: String,
        configuration: Configuration,
        jwt: String
    ) async throws {
        let host = environment == "development"
            ? "api.sandbox.push.apple.com"
            : "api.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(token)") else {
            throw PushError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(configuration.topic, forHTTPHeaderField: "apns-topic")
        request.setValue(
            APNSNotificationPayloadBuilder.pushType(for: envelope),
            forHTTPHeaderField: "apns-push-type"
        )
        request.setValue(
            APNSNotificationPayloadBuilder.priority(for: envelope),
            forHTTPHeaderField: "apns-priority"
        )
        request.setValue(
            APNSNotificationPayloadBuilder.collapseID(for: envelope),
            forHTTPHeaderField: "apns-collapse-id"
        )
        request.setValue(
            String(Int(envelope.expiresAt.timeIntervalSince1970)),
            forHTTPHeaderField: "apns-expiration"
        )
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try APNSNotificationPayloadBuilder.data(for: envelope)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = object?["reason"] as? String ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw PushError.rejected(status: http.statusCode, reason: reason)
        }
    }

    private func sendLiveActivity(
        payload: Data,
        token: String,
        environment: String,
        configuration: Configuration,
        jwt: String,
        priority: String,
        expiration: Date
    ) async throws {
        let host = environment == "development"
            ? "api.sandbox.push.apple.com"
            : "api.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(token)") else {
            throw PushError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue("\(configuration.topic).push-type.liveactivity", forHTTPHeaderField: "apns-topic")
        request.setValue("liveactivity", forHTTPHeaderField: "apns-push-type")
        request.setValue(priority, forHTTPHeaderField: "apns-priority")
        request.setValue(String(Int(expiration.timeIntervalSince1970)), forHTTPHeaderField: "apns-expiration")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = payload

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = object?["reason"] as? String ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw PushError.rejected(status: http.statusCode, reason: reason)
        }
    }
}

enum APNSNotificationPayloadBuilder {
    static func isVisibleAlert(_ envelope: RemoteAttentionPushEnvelope) -> Bool {
        if envelope.kind != .task { return envelope.state == .pending }
        guard let state = envelope.taskState else { return false }
        return state == .needsYou || state == .failed || state == .verified || state == .waitingForMac
    }

    static func shouldPushToStart(_ envelope: RemoteAttentionPushEnvelope) -> Bool {
        if envelope.kind == .task { return envelope.taskState == .needsYou }
        return envelope.state == .pending
    }

    static func usesVisibleNotificationFallback(
        for envelope: RemoteAttentionPushEnvelope,
        hasPushToStartToken: Bool
    ) -> Bool {
        isVisibleAlert(envelope) && (!shouldPushToStart(envelope) || !hasPushToStartToken)
    }

    static func data(for envelope: RemoteAttentionPushEnvelope) throws -> Data {
        var object = envelope.payloadFields
        if isVisibleAlert(envelope) {
            let copy = notificationCopy(for: envelope)
            object["aps"] = [
                "alert": [
                    "title": copy.title,
                    "body": copy.body,
                ],
                "sound": "default",
                "interruption-level": "time-sensitive",
            ]
            // One-release compatibility for the already-distributed Buddy.
            if envelope.kind == .approval {
                object["approvalId"] = envelope.requestID
            }
        } else {
            object["aps"] = ["content-available": 1]
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func collapseID(for envelope: RemoteAttentionPushEnvelope) -> String {
        let raw = "ci-\(envelope.kind.rawValue)-\(envelope.requestID)"
        return String(raw.prefix(64))
    }

    static func pushType(for envelope: RemoteAttentionPushEnvelope) -> String {
        isVisibleAlert(envelope) ? "alert" : "background"
    }

    static func priority(for envelope: RemoteAttentionPushEnvelope) -> String {
        isVisibleAlert(envelope) ? "10" : "5"
    }

    static func liveActivityStartData(for envelope: RemoteAttentionPushEnvelope) throws -> Data {
        let copy = notificationCopy(for: envelope)
        let aps: [String: Any] = [
            "timestamp": Int(envelope.issuedAt.timeIntervalSince1970),
            "event": "start",
            "attributes-type": "CodeIslandActivityAttributes",
            "attributes": ["sessionId": envelope.requestID],
            "content-state": try liveActivityContentState(for: envelope, status: pendingStatus(for: envelope.kind)),
            "input-push-token": 1,
            "stale-date": Int(envelope.expiresAt.timeIntervalSince1970),
            "relevance-score": 1.0,
            "alert": [
                "title": copy.title,
                "body": copy.body,
                "sound": "default",
            ],
        ]
        return try JSONSerialization.data(withJSONObject: ["aps": aps], options: [.sortedKeys])
    }

    static func liveActivityEndData(for envelope: RemoteAttentionPushEnvelope) throws -> Data {
        let terminalStatus = envelope.kind == .task ? taskStatus(envelope.taskState) : "idle"
        let aps: [String: Any] = [
            "timestamp": Int(envelope.issuedAt.timeIntervalSince1970),
            "event": "end",
            "dismissal-date": Int(envelope.issuedAt.timeIntervalSince1970),
            "content-state": try liveActivityContentState(for: envelope, status: terminalStatus),
        ]
        return try JSONSerialization.data(withJSONObject: ["aps": aps], options: [.sortedKeys])
    }

    static func liveActivityUpdateData(for envelope: RemoteAttentionPushEnvelope) throws -> Data {
        let aps: [String: Any] = [
            "timestamp": Int(envelope.issuedAt.timeIntervalSince1970),
            "event": "update",
            "content-state": try liveActivityContentState(for: envelope, status: taskStatus(envelope.taskState)),
            "stale-date": Int(envelope.expiresAt.timeIntervalSince1970),
            "relevance-score": envelope.taskState == .needsYou ? 1.0 : 0.7,
        ]
        return try JSONSerialization.data(withJSONObject: ["aps": aps], options: [.sortedKeys])
    }

    private struct LiveActivitySession: Encodable {
        let sessionId: String?
        let source: String
        let status: String
        let message: String?
        let updatedAt: Date
    }

    private struct LiveActivityContent: Encodable {
        let sequence: UInt64
        let source: String
        let status: String
        let message: String?
        let pendingAction: String?
        let taskID: String?
        let taskState: String?
        let sessions: [LiveActivitySession]
        let updatedAt: Date
    }

    private static func liveActivityContentState(
        for envelope: RemoteAttentionPushEnvelope,
        status: String
    ) throws -> [String: Any] {
        let isPending = envelope.state == .pending
        let isTask = envelope.kind == .task
        let message: String? = isTask
            ? taskMessage(envelope.taskState)
            : (isPending
                ? (envelope.kind == .approval
                    ? "Approval waiting · open Buddy privately"
                    : "Answer waiting · open Buddy privately")
                : "No action waiting")
        let content = LiveActivityContent(
            sequence: UInt64(max(0, envelope.issuedAt.timeIntervalSince1970 * 1_000)),
            source: "codeisland",
            status: status,
            message: message,
            pendingAction: isPending ? envelope.kind.rawValue : nil,
            taskID: isTask ? envelope.requestID : nil,
            taskState: envelope.taskState?.rawValue,
            sessions: isPending && !isTask ? [
                LiveActivitySession(
                    sessionId: envelope.requestID,
                    source: "codeisland",
                    status: status,
                    message: message,
                    updatedAt: envelope.issuedAt
                )
            ] : [],
            updatedAt: envelope.issuedAt
        )
        let encoded = try JSONEncoder().encode(content)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return object
    }

    private static func pendingStatus(for kind: RemoteAttentionKind) -> String {
        switch kind {
        case .approval: return "waitingApproval"
        case .question: return "waitingQuestion"
        case .task: return "waitingApproval"
        }
    }

    private static func taskStatus(_ state: RemoteTaskState?) -> String {
        switch state {
        case .waitingForMac: return "taskWaiting"
        case .queued: return "processing"
        case .working: return "running"
        case .needsYou: return "waitingApproval"
        case .verified: return "taskVerified"
        case .failed: return "taskFailed"
        case .cancelled, .none: return "idle"
        }
    }

    private static func taskMessage(_ state: RemoteTaskState?) -> String {
        switch state {
        case .needsYou: return "Your coding task needs a decision"
        case .verified: return "Your coding task passed its checks"
        case .failed: return "Your coding task needs review"
        case .waitingForMac: return "Your followed task lost its Mac connection"
        case .queued: return "Your coding task is queued"
        case .working: return "Your coding task is working"
        case .cancelled: return "Your coding task was cancelled"
        case .none: return "Coding task update"
        }
    }

    private static func notificationCopy(for envelope: RemoteAttentionPushEnvelope) -> (title: String, body: String) {
        if envelope.kind == .task {
            switch envelope.taskState {
            case .needsYou: return ("CodeIsland needs you", "Open Buddy to review the coding task privately.")
            case .verified: return ("CodeIsland task verified", "The followed task passed its reported checks.")
            case .failed: return ("CodeIsland task failed", "Open Buddy to review the failure privately.")
            case .waitingForMac: return ("CodeIsland lost your Mac", "Open Buddy to reconnect the followed task.")
            default: return ("CodeIsland task updated", "Open Buddy to review it privately.")
            }
        }
        let noun = envelope.kind == .approval ? "approval" : "answer"
        return ("CodeIsland needs your \(noun)", "Open Buddy to review it privately.")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
