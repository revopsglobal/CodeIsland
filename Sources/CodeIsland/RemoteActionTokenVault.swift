import CryptoKit
import Foundation
import Security

/// Issues short-lived, single-use action tokens bound to one device and one
/// permission request. Only a SHA-256 digest is retained outside process memory.
struct RemoteActionTokenVault {
    struct IssuedToken: Equatable {
        let rawValue: String
        let expiresAt: Date
    }

    enum ConsumeResult: Equatable {
        case accepted
        case expired
        case invalid
    }

    private struct Entry {
        let tokenHash: String
        let requestID: String
        let deviceID: String
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var issuedRawValues: [String: String] = [:]
    private let tokenGenerator: () -> String

    init(tokenGenerator: @escaping () -> String = Self.secureRandomToken) {
        self.tokenGenerator = tokenGenerator
    }

    mutating func issue(
        requestID: String,
        deviceID: String,
        now: Date = Date(),
        lifetime: TimeInterval = 120
    ) -> IssuedToken {
        discardExpired(before: now)
        let key = binding(requestID: requestID, deviceID: deviceID)
        if let existing = entries[key], let raw = issuedRawValues[key] {
            return IssuedToken(rawValue: raw, expiresAt: existing.expiresAt)
        }

        let raw = tokenGenerator()
        let expiresAt = now.addingTimeInterval(lifetime)
        entries[key] = Entry(
            tokenHash: Self.hash(raw),
            requestID: requestID,
            deviceID: deviceID,
            expiresAt: expiresAt
        )
        issuedRawValues[key] = raw
        return IssuedToken(rawValue: raw, expiresAt: expiresAt)
    }

    mutating func consume(
        requestID: String,
        deviceID: String,
        token: String,
        now: Date = Date()
    ) -> ConsumeResult {
        let key = binding(requestID: requestID, deviceID: deviceID)
        guard let entry = entries[key],
              entry.requestID == requestID,
              entry.deviceID == deviceID,
              Self.constantTimeEqual(entry.tokenHash, Self.hash(token))
        else {
            return .invalid
        }

        entries.removeValue(forKey: key)
        issuedRawValues.removeValue(forKey: key)
        return entry.expiresAt > now ? .accepted : .expired
    }

    mutating func removeAll(forRequestID requestID: String) {
        remove(keys: entries.compactMap { key, entry in
            entry.requestID == requestID ? key : nil
        })
    }

    private mutating func discardExpired(before date: Date) {
        remove(keys: entries.compactMap { key, entry in
            entry.expiresAt <= date ? key : nil
        })
    }

    private mutating func remove(keys: [String]) {
        for key in keys {
            entries.removeValue(forKey: key)
            issuedRawValues.removeValue(forKey: key)
        }
    }

    private func binding(requestID: String, deviceID: String) -> String {
        "\(deviceID):\(requestID)"
    }

    private static func secureRandomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
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
