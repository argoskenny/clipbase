import Foundation

protocol TokenStoring {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

final class UserDefaultsTokenStore: TokenStoring {
    static let defaultsKey = "clipbase.sessionToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadToken() throws -> String? {
        guard let token = normalized(defaults.string(forKey: Self.defaultsKey)) else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return nil
        }

        return token
    }

    func saveToken(_ token: String) throws {
        guard let token = normalized(token) else {
            try deleteToken()
            return
        }

        defaults.set(token, forKey: Self.defaultsKey)
    }

    func deleteToken() throws {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
