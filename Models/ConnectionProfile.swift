import Foundation

public struct ConnectionProfile: Equatable, Codable {
    public static let defaultExternalIPCheckURL = "https://api.ipify.org?format=text"

    public var name: String = "Default"
    public var host: String = ""
    public var username: String = ""
    public var sshPort: Int = 22
    public var localSocksPort: Int = 1080
    public var useKeyAuthentication: Bool = false
    public var externalIPCheckEnabled: Bool = true
    public var externalIPCheckURL: String = Self.defaultExternalIPCheckURL

    public var destination: String {
        "\(username)@\(host)"
    }

    public var isValid: Bool {
        !host.isEmpty && !username.isEmpty && (1...65535).contains(sshPort) && (1...65535).contains(localSocksPort)
    }

    public var hasValidExternalIPCheckURL: Bool {
        guard externalIPCheckEnabled else { return true }
        guard let url = URL(string: externalIPCheckURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }
}
