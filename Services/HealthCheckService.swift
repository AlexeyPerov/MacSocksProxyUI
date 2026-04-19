import CFNetwork
import Foundation

final class HealthCheckService {
    private let portProbeService: PortProbeService
    private let ipCheckURL: URL

    init(
        portProbeService: PortProbeService = PortProbeService(),
        ipCheckURL: URL = URL(string: "https://api.ipify.org?format=text")!
    ) {
        self.portProbeService = portProbeService
        self.ipCheckURL = ipCheckURL
    }

    func checkSocksPort(_ port: Int) async -> Bool {
        await portProbeService.isListening(port: port)
    }

    /// Fetches the public IP as seen through the local SOCKS proxy (SSH `-D`).
    func fetchExternalIPThroughSocks(localPort: Int, timeout: TimeInterval = 12) async -> String? {
        guard (1...65535).contains(localPort) else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFNetworkProxiesSOCKSEnable as String: true,
            kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
            kCFNetworkProxiesSOCKSPort as String: NSNumber(value: localPort),
        ]
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 2
        config.waitsForConnectivity = true

        let session = URLSession(configuration: config)

        do {
            let (data, response) = try await session.data(from: ipCheckURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    /// SOCKS port must accept TCP; external IP is optional for degraded-but-up scenarios.
    func performHealthCheck(localPort: Int) async -> (socksListening: Bool, externalIP: String?) {
        let socksListening = await checkSocksPort(localPort)
        guard socksListening else {
            return (false, nil)
        }
        let ip = await fetchExternalIPThroughSocks(localPort: localPort)
        return (true, ip)
    }
}
