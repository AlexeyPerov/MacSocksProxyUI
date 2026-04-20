import Foundation

final class DiagnosticsStore {
    private let maxEntries: Int
    private var entries: [String] = []

    init(maxEntries: Int = 250) {
        self.maxEntries = maxEntries
    }

    func append(_ entry: String) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func render(status: ProxyStatus, profile: ConnectionProfile, externalIP: String) -> String {
        var lines: [String] = [
            "Status: \(status.title)",
            "Destination: \(profile.destination)",
            "SSH Port: \(profile.sshPort)",
            "SOCKS Port: \(profile.localSocksPort)",
            "External IP: \(externalIP)"
        ]
        if let details = status.details {
            lines.append("Details: \(details)")
        }
        lines.append("---- recent ssh stderr ----")
        lines.append(contentsOf: entries.suffix(100))
        return lines.joined(separator: "\n")
    }
}
