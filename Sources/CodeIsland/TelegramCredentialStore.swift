import Foundation
import Security

protocol TelegramSecretBackend {
    func read(service: String, account: String) throws -> String?
    func write(_ value: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

struct TelegramCredentialStore {
    static let service = "com.codeisland.telegram.bot-token"
    static let account = "default"

    private let backend: any TelegramSecretBackend
    private let defaults: UserDefaults

    init(
        backend: any TelegramSecretBackend = KeychainTelegramSecretBackend(),
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.defaults = defaults
    }

    func save(_ value: String) throws {
        try backend.write(value, service: Self.service, account: Self.account)
    }

    func load() throws -> String? {
        try backend.read(service: Self.service, account: Self.account)
    }

    func delete() throws {
        try backend.delete(service: Self.service, account: Self.account)
    }

    /// Moves the legacy preference only after Keychain confirms the write.
    /// Existing Keychain state always wins and leaves the preference untouched.
    func loadMigratingLegacyValue() throws -> String? {
        if let stored = try load() {
            return stored
        }

        guard let legacy = defaults.string(forKey: SettingsKey.remoteApprovalTelegramBotToken),
              !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        try save(legacy)
        defaults.removeObject(forKey: SettingsKey.remoteApprovalTelegramBotToken)
        return legacy
    }
}

struct KeychainTelegramSecretBackend: TelegramSecretBackend {
    private enum KeychainError: LocalizedError {
        case invalidData
        case unavailable(OSStatus)

        var errorDescription: String? {
            "Telegram credential storage is unavailable"
        }
    }

    func read(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unavailable(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.invalidData
        }
        return value
    }

    func write(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unavailable(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unavailable(addStatus)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unavailable(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
