import Combine
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

    func notify(requestID: String, source: String, tool: String, devices: [RemoteApprovalDevice]) {
        let targets = devices.filter { $0.pushToken?.isEmpty == false }
        guard !targets.isEmpty else { return }
        guard let configuration = configuration() else { return }

        Task {
            do {
                let jwt = try authorizationToken(configuration: configuration)
                for device in targets {
                    guard let token = device.pushToken else { continue }
                    try await send(
                        requestID: requestID,
                        source: source,
                        tool: tool,
                        token: token,
                        environment: device.pushEnvironment ?? "production",
                        configuration: configuration,
                        jwt: jwt
                    )
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
        requestID: String,
        source: String,
        tool: String,
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
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue("approval-\(requestID)", forHTTPHeaderField: "apns-collapse-id")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "aps": [
                "alert": [
                    "title": "CodeIsland approval waiting",
                    "body": "Open Buddy to review it privately."
                ],
                "sound": "default",
                "interruption-level": "time-sensitive"
            ],
            "approvalId": requestID
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PushError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = object?["reason"] as? String ?? String(data: data, encoding: .utf8) ?? "unknown"
            throw PushError.rejected(status: http.statusCode, reason: reason)
        }
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
