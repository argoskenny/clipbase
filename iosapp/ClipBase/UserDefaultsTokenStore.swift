import Foundation

protocol TokenStoring {
    func readToken() -> String?
    func saveToken(_ token: String) throws
    func deleteToken()
}

final class UserDefaultsTokenStore: TokenStoring {
    static let defaultsKey = "clipbase.sessionToken"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func readToken() -> String? {
        guard let token = normalized(defaults.string(forKey: Self.defaultsKey)) else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return nil
        }

        return token
    }

    func saveToken(_ token: String) throws {
        guard let token = normalized(token) else {
            deleteToken()
            return
        }

        defaults.set(token, forKey: Self.defaultsKey)
    }

    func deleteToken() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
