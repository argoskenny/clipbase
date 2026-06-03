import Foundation
import Security

protocol TokenStoring {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

protocol KeychainTokenBackend {
    func read(service: String, account: String) throws -> String?
    func save(_ token: String, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

final class KeychainTokenStore: TokenStoring {
    static let legacyDefaultsKey = "clipbase.sessionToken"

    let service: String
    let account: String

    private let defaults: UserDefaults
    private let backend: KeychainTokenBackend

    init(
        service: String = "com.clipbase.macapp",
        account: String = "session-token",
        defaults: UserDefaults = .standard,
        backend: KeychainTokenBackend = SystemKeychainTokenBackend()
    ) {
        self.service = service
        self.account = account
        self.defaults = defaults
        self.backend = backend
    }

    func loadToken() throws -> String? {
        if let token = normalized(try backend.read(service: service, account: account)) {
            return token
        }

        guard let legacyToken = normalized(defaults.string(forKey: Self.legacyDefaultsKey)) else {
            defaults.removeObject(forKey: Self.legacyDefaultsKey)
            return nil
        }

        try backend.save(legacyToken, service: service, account: account)
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
        return legacyToken
    }

    func saveToken(_ token: String) throws {
        guard let token = normalized(token) else {
            try deleteToken()
            return
        }

        try backend.save(token, service: service, account: account)
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
    }

    func deleteToken() throws {
        try backend.delete(service: service, account: account)
        defaults.removeObject(forKey: Self.legacyDefaultsKey)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct SystemKeychainTokenBackend: KeychainTokenBackend {
    func read(service: String, account: String) throws -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unhandledStatus(status)
        }
        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.invalidStoredData
        }
        return token
    }

    func save(_ token: String, service: String, account: String) throws {
        try delete(service: service, account: account)

        guard let data = token.data(using: .utf8) else {
            throw KeychainTokenStoreError.invalidStoredData
        }

        var attributes = baseQuery(service: service, account: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unhandledStatus(status)
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unhandledStatus(status)
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

enum KeychainTokenStoreError: LocalizedError, Equatable {
    case invalidStoredData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidStoredData:
            return "Keychain 中的登入 token 格式無效"
        case .unhandledStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知 Keychain 錯誤"
            return "\(message)（\(status)）"
        }
    }
}
