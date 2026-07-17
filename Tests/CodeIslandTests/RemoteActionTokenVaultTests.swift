import XCTest
@testable import CodeIsland

final class RemoteActionTokenVaultTests: XCTestCase {
    func testTokenIsStableUntilExpiryAndSingleUse() {
        let now = Date(timeIntervalSince1970: 1_000)
        var generated = ["first-token", "second-token"].makeIterator()
        var vault = RemoteActionTokenVault(tokenGenerator: { generated.next()! })

        let first = vault.issue(requestID: "request-a", deviceID: "phone-a", now: now)
        let repeated = vault.issue(
            requestID: "request-a",
            deviceID: "phone-a",
            now: now.addingTimeInterval(30)
        )

        XCTAssertEqual(first, repeated)
        XCTAssertEqual(
            vault.consume(requestID: "request-a", deviceID: "phone-a", token: first.rawValue, now: now),
            .accepted
        )
        XCTAssertEqual(
            vault.consume(requestID: "request-a", deviceID: "phone-a", token: first.rawValue, now: now),
            .invalid,
            "a remote decision token must not be replayable"
        )
    }

    func testTokenIsBoundToRequestAndDevice() {
        let now = Date(timeIntervalSince1970: 2_000)
        var vault = RemoteActionTokenVault(tokenGenerator: { "bound-token" })
        let issued = vault.issue(requestID: "request-a", deviceID: "phone-a", now: now)

        XCTAssertEqual(
            vault.consume(requestID: "request-b", deviceID: "phone-a", token: issued.rawValue, now: now),
            .invalid
        )
        XCTAssertEqual(
            vault.consume(requestID: "request-a", deviceID: "phone-b", token: issued.rawValue, now: now),
            .invalid
        )
        XCTAssertEqual(
            vault.consume(requestID: "request-a", deviceID: "phone-a", token: issued.rawValue, now: now),
            .accepted
        )
    }

    func testExpiredTokenIsRejectedAndConsumed() {
        let now = Date(timeIntervalSince1970: 3_000)
        var vault = RemoteActionTokenVault(tokenGenerator: { "expiring-token" })
        let issued = vault.issue(
            requestID: "request-a",
            deviceID: "phone-a",
            now: now,
            lifetime: 10
        )

        XCTAssertEqual(
            vault.consume(
                requestID: "request-a",
                deviceID: "phone-a",
                token: issued.rawValue,
                now: now.addingTimeInterval(11)
            ),
            .expired
        )
        XCTAssertEqual(
            vault.consume(
                requestID: "request-a",
                deviceID: "phone-a",
                token: issued.rawValue,
                now: now.addingTimeInterval(11)
            ),
            .invalid
        )
    }
}
