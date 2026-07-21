import CryptoKit
import Foundation

struct TelegramIdentity: Equatable {
    let userID: Int64
    let firstName: String?
    let username: String?
    let languageCode: String?
}

struct TelegramInitDataValidator {
    private let botToken: String

    init(botToken: String) {
        self.botToken = botToken
    }

    func validate(
        _ rawInitData: String,
        allowedUserID: Int64,
        now: Date = Date()
    ) throws -> TelegramIdentity {
        guard !botToken.isEmpty, allowedUserID > 0 else {
            throw ValidationError.invalid
        }

        let fields = try parseQuery(rawInitData)
        guard let suppliedHash = fields["hash"],
              let suppliedHashBytes = Self.decodeSHA256Hex(suppliedHash)
        else {
            throw ValidationError.invalid
        }

        let checkString = fields
            .filter { $0.key != "hash" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        let secret = HMAC<SHA256>.authenticationCode(
            for: Data(botToken.utf8),
            using: SymmetricKey(data: Data("WebAppData".utf8))
        )
        let expectedHash = Array(HMAC<SHA256>.authenticationCode(
            for: Data(checkString.utf8),
            using: SymmetricKey(data: Data(secret))
        ))
        guard Self.constantTimeEqual(expectedHash, suppliedHashBytes) else {
            throw ValidationError.invalid
        }

        guard let authDateValue = fields["auth_date"],
              let authDateSeconds = TimeInterval(authDateValue)
        else {
            throw ValidationError.invalid
        }
        let age = now.timeIntervalSince1970 - authDateSeconds
        guard age <= 60, age >= -15 else {
            throw ValidationError.invalid
        }

        guard let userValue = fields["user"],
              let userData = userValue.data(using: .utf8),
              let user = try? JSONDecoder().decode(TelegramUser.self, from: userData),
              user.id == allowedUserID
        else {
            throw ValidationError.invalid
        }

        return TelegramIdentity(
            userID: user.id,
            firstName: user.firstName,
            username: user.username,
            languageCode: user.languageCode
        )
    }

    private enum ValidationError: LocalizedError {
        case invalid

        var errorDescription: String? {
            "Telegram authorization could not be verified"
        }
    }

    private struct TelegramUser: Decodable {
        let id: Int64
        let firstName: String?
        let username: String?
        let languageCode: String?

        enum CodingKeys: String, CodingKey {
            case id
            case firstName = "first_name"
            case username
            case languageCode = "language_code"
        }
    }

    private func parseQuery(_ raw: String) throws -> [String: String] {
        guard !raw.isEmpty, raw.utf8.count <= 16_384 else {
            throw ValidationError.invalid
        }

        var result: [String: String] = [:]
        for component in raw.split(separator: "&", omittingEmptySubsequences: false) {
            guard !component.isEmpty,
                  let equals = component.firstIndex(of: "=")
            else {
                throw ValidationError.invalid
            }

            let encodedKey = String(component[..<equals])
            let encodedValue = String(component[component.index(after: equals)...])
            guard let key = Self.decodeQueryComponent(encodedKey),
                  let value = Self.decodeQueryComponent(encodedValue),
                  !key.isEmpty,
                  result[key] == nil
            else {
                throw ValidationError.invalid
            }
            result[key] = value
        }
        return result
    }

    private static func decodeQueryComponent(_ value: String) -> String? {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    private static func decodeSHA256Hex(_ value: String) -> [UInt8]? {
        let bytes = Array(value.utf8)
        guard bytes.count == 64 else { return nil }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(32)
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = hexNibble(bytes[index]),
                  let low = hexNibble(bytes[index + 1])
            else {
                return nil
            }
            decoded.append((high << 4) | low)
        }
        return decoded
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }
}
