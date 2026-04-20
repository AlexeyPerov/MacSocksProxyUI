import CFNetwork
import Foundation

actor HealthCheckService {
    private let portProbeService: PortProbeService
    private var externalIPCheckEnabled: Bool
    private var ipCheckURL: URL?
    private var cachedSession: URLSession?
    private var cachedSessionPort: Int?
    private var cachedSessionTimeout: TimeInterval?

    init(
        portProbeService: PortProbeService = PortProbeService(),
        ipCheckURL: URL = URL(string: ConnectionProfile.defaultExternalIPCheckURL)!,
        externalIPCheckEnabled: Bool = true
    ) {
        self.portProbeService = portProbeService
        self.ipCheckURL = ipCheckURL
        self.externalIPCheckEnabled = externalIPCheckEnabled
    }

    func checkSocksPort(_ port: Int) async -> Bool {
        await portProbeService.isListening(port: port)
    }

    func updateExternalIPCheck(enabled: Bool, urlString: String) {
        externalIPCheckEnabled = enabled
        ipCheckURL = Self.validatedExternalIPURL(from: urlString)
    }

    static func validatedExternalIPURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Fetches the public IP as seen through the local SOCKS proxy (SSH `-D`).
    func fetchExternalIPThroughSocks(localPort: Int, timeout: TimeInterval = 12) async -> String? {
        guard (1...65535).contains(localPort) else { return nil }
        guard externalIPCheckEnabled else { return nil }
        guard let ipCheckURL else { return nil }

        let session = sessionForSocks(localPort: localPort, timeout: timeout)

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

    private func sessionForSocks(localPort: Int, timeout: TimeInterval) -> URLSession {
        if let cachedSession, cachedSessionPort == localPort, cachedSessionTimeout == timeout {
            return cachedSession
        }

        cachedSession?.invalidateAndCancel()

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
        cachedSession = session
        cachedSessionPort = localPort
        cachedSessionTimeout = timeout
        return session
    }
}
