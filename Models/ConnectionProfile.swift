import Foundation

struct ConnectionProfile: Equatable, Codable {
    var name: String = "Default"
    var host: String = ""
    var username: String = ""
    var sshPort: Int = 22
    var localSocksPort: Int = 1080
    var useKeyAuthentication: Bool = false

    var destination: String {
        "\(username)@\(host)"
    }

    var isValid: Bool {
        !host.isEmpty && !username.isEmpty && (1...65535).contains(sshPort) && (1...65535).contains(localSocksPort)
    }
}
