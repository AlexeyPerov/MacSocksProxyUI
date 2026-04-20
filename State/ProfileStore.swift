import Foundation

final class ProfileStore {
    private enum Constants {
        static let legacyUserDefaultsKey = "connectionProfile"
        static let secureService = "com.macproxyui.profile"
        static let secureAccount = "active-profile-v1"
    }

    private let userDefaults: UserDefaults
    private let secureStore: SecureDataStore

    init(
        userDefaults: UserDefaults = .standard,
        secureStore: SecureDataStore
    ) {
        self.userDefaults = userDefaults
        self.secureStore = secureStore
    }

    func load() -> ConnectionProfile? {
        if let secureProfile = loadFromSecureStore() {
            return secureProfile
        }

        guard let legacyData = userDefaults.data(forKey: Constants.legacyUserDefaultsKey),
              let legacyProfile = try? JSONDecoder().decode(ConnectionProfile.self, from: legacyData) else {
            return nil
        }

        // One-time migration from plaintext UserDefaults into Keychain-backed storage.
        save(legacyProfile)
        userDefaults.removeObject(forKey: Constants.legacyUserDefaultsKey)
        return legacyProfile
    }

    func save(_ profile: ConnectionProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? secureStore.saveData(data, account: Constants.secureAccount, service: Constants.secureService)
    }

    private func loadFromSecureStore() -> ConnectionProfile? {
        guard let data = try? secureStore.loadData(account: Constants.secureAccount, service: Constants.secureService),
              let profile = try? JSONDecoder().decode(ConnectionProfile.self, from: data) else {
            return nil
        }
        return profile
    }
}
