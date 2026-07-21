import CryptoKit
import XCTest
@testable import CodeIsland

final class TelegramInitDataValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let allowedUserID: Int64 = 8_567_114_601

    func testValidSignedInitDataReturnsAllowlistedIdentity() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(userID: allowedUserID, authDate: now)

        let identity = try TelegramInitDataValidator(botToken: fixture.botToken)
            .validate(raw, allowedUserID: allowedUserID, now: now)

        XCTAssertEqual(identity.userID, allowedUserID)
        XCTAssertEqual(identity.username, "greg")
    }

    func testTamperedUserJSONIsRejected() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(userID: allowedUserID, authDate: now)
        let tampered = raw.replacingOccurrences(
            of: fixture.encoded(fixture.userJSON(userID: allowedUserID)),
            with: fixture.encoded(fixture.userJSON(userID: allowedUserID + 1))
        )

        XCTAssertThrowsError(
            try TelegramInitDataValidator(botToken: fixture.botToken)
                .validate(tampered, allowedUserID: allowedUserID, now: now)
        )
    }

    func testMissingAndMalformedHashesAreRejected() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(userID: allowedUserID, authDate: now)
        let withoutHash = raw.split(separator: "&")
            .filter { !$0.hasPrefix("hash=") }
            .joined(separator: "&")
        let malformedHash = raw.split(separator: "&")
            .map { $0.hasPrefix("hash=") ? "hash=not-a-signature" : String($0) }
            .joined(separator: "&")

        for candidate in [withoutHash, malformedHash] {
            XCTAssertThrowsError(
                try TelegramInitDataValidator(botToken: fixture.botToken)
                    .validate(candidate, allowedUserID: allowedUserID, now: now)
            )
        }
    }

    func testStaleAuthDateIsRejected() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(
            userID: allowedUserID,
            authDate: now.addingTimeInterval(-61)
        )

        XCTAssertThrowsError(
            try TelegramInitDataValidator(botToken: fixture.botToken)
                .validate(raw, allowedUserID: allowedUserID, now: now)
        )
    }

    func testFutureAuthDateOutsideToleranceIsRejected() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(
            userID: allowedUserID,
            authDate: now.addingTimeInterval(16)
        )

        XCTAssertThrowsError(
            try TelegramInitDataValidator(botToken: fixture.botToken)
                .validate(raw, allowedUserID: allowedUserID, now: now)
        )
    }

    func testWrongAllowlistedUserIsRejected() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(userID: allowedUserID, authDate: now)

        XCTAssertThrowsError(
            try TelegramInitDataValidator(botToken: fixture.botToken)
                .validate(raw, allowedUserID: allowedUserID + 1, now: now)
        )
    }

    func testMalformedPercentEncodingIsRejectedWithoutEchoingInput() throws {
        let fixture = Fixture()
        let raw = fixture.signedInitData(userID: allowedUserID, authDate: now) + "&bad=%ZZ"

        XCTAssertThrowsError(
            try TelegramInitDataValidator(botToken: fixture.botToken)
                .validate(raw, allowedUserID: allowedUserID, now: now)
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains(raw))
            XCTAssertFalse(error.localizedDescription.contains(fixture.botToken))
        }
    }
}

private struct Fixture {
    let botToken = "123456789:telegram-test-secret"

    func signedInitData(userID: Int64, authDate: Date) -> String {
        let fields = [
            "auth_date": String(Int64(authDate.timeIntervalSince1970)),
            "query_id": "AAHdF6IQAAAAAN0XohDhrOrc",
            "user": userJSON(userID: userID)
        ]
        let checkString = fields.keys.sorted()
            .map { "\($0)=\(fields[$0]!)" }
            .joined(separator: "\n")
        let secret = HMAC<SHA256>.authenticationCode(
            for: Data(botToken.utf8),
            using: SymmetricKey(data: Data("WebAppData".utf8))
        )
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(checkString.utf8),
            using: SymmetricKey(data: Data(secret))
        ).map { String(format: "%02x", $0) }.joined()

        let queryFields = [
            ("user", fields["user"]!),
            ("query_id", fields["query_id"]!),
            ("auth_date", fields["auth_date"]!),
            ("hash", signature)
        ]
        return queryFields
            .map { "\(encoded($0.0))=\(encoded($0.1))" }
            .joined(separator: "&")
    }

    func userJSON(userID: Int64) -> String {
        "{\"id\":\(userID),\"first_name\":\"Greg\",\"username\":\"greg\",\"language_code\":\"en\"}"
    }

    func encoded(_ value: String) -> String {
        value.addingPercentEncoding(
            withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        )!
    }
}
