import Foundation
import Security

protocol SecureDataStore {
    func saveData(_ data: Data, account: String, service: String) throws
    func loadData(account: String, service: String) throws -> Data?
    func deleteData(account: String, service: String) throws
}

enum KeychainServiceError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidPasswordData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain error (OSStatus \(status))."
        case .invalidPasswordData:
            return "Could not read password data from Keychain."
        }
    }
}

final class KeychainService {
    /// Must match `AskpassHelper` target so the helper can read the same items.
    static let serviceIdentifier = "com.macproxyui.credentials"

    /// Stable per-connection account string (host + port + user).
    static func accountIdentifier(for profile: ConnectionProfile) -> String {
        "\(profile.username)@\(profile.host):\(profile.sshPort)"
    }

    func savePassword(_ password: String, account: String) throws {
        try saveData(Data(password.utf8), account: account, service: Self.serviceIdentifier)
    }

    func loadPassword(account: String) throws -> String? {
        guard let data = try loadData(account: account, service: Self.serviceIdentifier) else {
            return nil
        }
        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.invalidPasswordData
        }
        return password
    }

    func deletePassword(account: String) throws {
        try deleteData(account: account, service: Self.serviceIdentifier)
    }

    func saveData(_ data: Data, account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            status = SecItemAdd(add as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func loadData(account: String, service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
        return result as? Data
    }

    func deleteData(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.unexpectedStatus(status)
        }
    }

    func hasPassword(account: String) -> Bool {
        (try? loadPassword(account: account)) != nil
    }
}

extension KeychainService: SecureDataStore {}
