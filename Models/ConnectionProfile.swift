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
    public var externalIPCheckURLs: [String] = [Self.defaultExternalIPCheckURL]

    public var destination: String {
        "\(username)@\(host)"
    }

    public var isValid: Bool {
        !host.isEmpty && !username.isEmpty && (1...65535).contains(sshPort) && (1...65535).contains(localSocksPort)
    }

    public var externalIPCheckURL: String {
        get {
            externalIPCheckURLs.first ?? Self.defaultExternalIPCheckURL
        }
        set {
            externalIPCheckURLs = [newValue]
        }
    }

    public var normalizedExternalIPCheckURLs: [String] {
        let normalized = externalIPCheckURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? [Self.defaultExternalIPCheckURL] : normalized
    }

    public var hasValidExternalIPCheckURL: Bool {
        guard externalIPCheckEnabled else { return true }
        return normalizedExternalIPCheckURLs.allSatisfy { rawValue in
            guard let url = URL(string: rawValue) else { return false }
            return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case host
        case username
        case sshPort
        case localSocksPort
        case useKeyAuthentication
        case externalIPCheckEnabled
        case externalIPCheckURL
        case externalIPCheckURLs
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Default"
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        localSocksPort = try container.decodeIfPresent(Int.self, forKey: .localSocksPort) ?? 1080
        useKeyAuthentication = try container.decodeIfPresent(Bool.self, forKey: .useKeyAuthentication) ?? false
        externalIPCheckEnabled = try container.decodeIfPresent(Bool.self, forKey: .externalIPCheckEnabled) ?? true

        if let urls = try container.decodeIfPresent([String].self, forKey: .externalIPCheckURLs), !urls.isEmpty {
            externalIPCheckURLs = urls
        } else if let legacyURL = try container.decodeIfPresent(String.self, forKey: .externalIPCheckURL) {
            externalIPCheckURLs = [legacyURL]
        } else {
            externalIPCheckURLs = [Self.defaultExternalIPCheckURL]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(username, forKey: .username)
        try container.encode(sshPort, forKey: .sshPort)
        try container.encode(localSocksPort, forKey: .localSocksPort)
        try container.encode(useKeyAuthentication, forKey: .useKeyAuthentication)
        try container.encode(externalIPCheckEnabled, forKey: .externalIPCheckEnabled)
        try container.encode(normalizedExternalIPCheckURLs, forKey: .externalIPCheckURLs)
    }
}
