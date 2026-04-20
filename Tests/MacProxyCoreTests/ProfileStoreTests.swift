import XCTest
@testable import MacProxyCore

private final class InMemorySecureStore: SecureDataStore {
    private var storage: [String: Data] = [:]

    func saveData(_ data: Data, account: String, service: String) throws {
        storage["\(service)::\(account)"] = data
    }

    func loadData(account: String, service: String) throws -> Data? {
        storage["\(service)::\(account)"]
    }

    func deleteData(account: String, service: String) throws {
        storage.removeValue(forKey: "\(service)::\(account)")
    }
}

final class ProfileStoreTests: XCTestCase {
    func testSaveAndLoadRoundTripUsesSecureStore() {
        let suiteName = "ProfileStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let secureStore = InMemorySecureStore()
        let store = ProfileStore(userDefaults: defaults, secureStore: secureStore)
        var profile = ConnectionProfile()
        profile.host = "example.com"
        profile.username = "alex"
        profile.externalIPCheckURL = "https://example.com/ip"

        store.save(profile)
        let loaded = store.load()
        XCTAssertEqual(loaded, profile)
        XCTAssertNil(defaults.data(forKey: "connectionProfile"))
    }

    func testLegacyUserDefaultsDataMigratesToSecureStore() throws {
        let suiteName = "ProfileStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var profile = ConnectionProfile()
        profile.host = "legacy.example"
        profile.username = "old-user"
        let encoded = try JSONEncoder().encode(profile)
        defaults.set(encoded, forKey: "connectionProfile")

        let secureStore = InMemorySecureStore()
        let store = ProfileStore(userDefaults: defaults, secureStore: secureStore)
        let migrated = store.load()
        XCTAssertEqual(migrated, profile)
        XCTAssertNil(defaults.data(forKey: "connectionProfile"))

        // Ensure the migrated profile is now sourced from the secure store.
        let loadedAgain = store.load()
        XCTAssertEqual(loadedAgain, profile)
    }
}
