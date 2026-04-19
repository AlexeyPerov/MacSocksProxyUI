import Darwin
import Foundation
import LocalAuthentication
import Security

/// Minimal SSH_ASKPASS helper: prints the Keychain password for `MACPROXYUI_KEYCHAIN_ACCOUNT` to stdout.
/// Must stay in sync with `KeychainService.serviceIdentifier`.
private let serviceIdentifier = "com.macproxyui.credentials"

@main
enum AskpassHelperEntry {
    static func main() {
        guard let account = ProcessInfo.processInfo.environment["MACPROXYUI_KEYCHAIN_ACCOUNT"],
              !account.isEmpty else {
            fputs("MacProxyUI askpass: missing MACPROXYUI_KEYCHAIN_ACCOUNT\n", stderr)
            exit(2)
        }

        let authContext = LAContext()
        authContext.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: authContext
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecInteractionNotAllowed {
            fputs("MacProxyUI askpass: keychain requires user interaction (unlock the app or session first)\n", stderr)
            exit(3)
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            fputs("MacProxyUI askpass: could not load password from Keychain\n", stderr)
            exit(1)
        }

        FileHandle.standardOutput.write(Data((password + "\n").utf8))
        fflush(stdout)
        exit(0)
    }
}
