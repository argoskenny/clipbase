import Foundation

final class UserDefaultsTokenStore {
    private let defaults: UserDefaults
    private let key = "clipbase.sessionToken"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadToken() -> String? {
        let token = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    func saveToken(_ token: String) {
        defaults.set(token, forKey: key)
    }

    func deleteToken() {
        defaults.removeObject(forKey: key)
    }
}
