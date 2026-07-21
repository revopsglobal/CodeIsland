import XCTest
@testable import CodeIsland

final class TelegramCredentialStoreTests: XCTestCase {
    func testSaveLoadAndDeleteUseSecretBackend() throws {
        let fixture = Fixture()

        try fixture.store.save("123:secret")
        XCTAssertEqual(try fixture.store.load(), "123:secret")

        try fixture.store.delete()
        XCTAssertNil(try fixture.store.load())
    }

    func testMigrationMovesLegacyTokenAndDeletesPreferenceAfterSuccessfulWrite() throws {
        let fixture = Fixture()
        fixture.defaults.set("123:secret", forKey: SettingsKey.remoteApprovalTelegramBotToken)

        XCTAssertEqual(try fixture.store.loadMigratingLegacyValue(), "123:secret")
        XCTAssertEqual(fixture.backend.value, "123:secret")
        XCTAssertNil(fixture.defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken))
    }

    func testMigrationFailurePreservesLegacyPreference() throws {
        let fixture = Fixture()
        fixture.backend.writeError = TestError.writeFailed
        fixture.defaults.set("123:secret", forKey: SettingsKey.remoteApprovalTelegramBotToken)

        XCTAssertThrowsError(try fixture.store.loadMigratingLegacyValue()) { error in
            XCTAssertFalse(error.localizedDescription.contains("123:secret"))
        }
        XCTAssertEqual(
            fixture.defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken),
            "123:secret"
        )
    }

    func testExistingKeychainValueWinsWithoutReadingLegacyPreference() throws {
        let fixture = Fixture()
        fixture.backend.value = "keychain-token"
        fixture.defaults.set("legacy-token", forKey: SettingsKey.remoteApprovalTelegramBotToken)

        XCTAssertEqual(try fixture.store.loadMigratingLegacyValue(), "keychain-token")
        XCTAssertEqual(
            fixture.defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken),
            "legacy-token"
        )
    }

    private final class Fixture {
        let suiteName = "TelegramCredentialStoreTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let backend = MemoryTelegramSecretBackend()
        lazy var store = TelegramCredentialStore(backend: backend, defaults: defaults)

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

private enum TestError: LocalizedError {
    case writeFailed

    var errorDescription: String? { "Secret storage failed" }
}

private final class MemoryTelegramSecretBackend: TelegramSecretBackend {
    var value: String?
    var writeError: Error?

    func read(service _: String, account _: String) throws -> String? {
        value
    }

    func write(_ value: String, service _: String, account _: String) throws {
        if let writeError { throw writeError }
        self.value = value
    }

    func delete(service _: String, account _: String) throws {
        value = nil
    }
}
