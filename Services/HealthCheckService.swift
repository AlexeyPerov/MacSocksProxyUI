import CFNetwork
import Foundation

enum ExternalIPFailureReason: Equatable {
    case timeout
    case dns
    case tls
    case httpStatus(Int)
    case proxyConnect
    case emptyBody
    case unknown

    var description: String {
        switch self {
        case .timeout:
            return "timeout"
        case .dns:
            return "dns"
        case .tls:
            return "tls"
        case .httpStatus(let statusCode):
            return "http_\(statusCode)"
        case .proxyConnect:
            return "proxy_connect"
        case .emptyBody:
            return "empty_body"
        case .unknown:
            return "unknown"
        }
    }
}

struct ExternalIPFailureDetail: Equatable {
    let endpoint: URL
    let reason: ExternalIPFailureReason
}

enum ExternalIPCheckResult: Equatable {
    case success(ip: String, endpoint: URL)
    case allFailed([ExternalIPFailureDetail])

    var summary: String {
        switch self {
        case .success(let ip, let endpoint):
            return "success ip=\(ip) endpoint=\(endpoint.host ?? endpoint.absoluteString)"
        case .allFailed(let details):
            let compact = details
                .map { detail in
                    let host = detail.endpoint.host ?? detail.endpoint.absoluteString
                    return "\(host):\(detail.reason.description)"
                }
                .joined(separator: ", ")
            return compact.isEmpty ? "all endpoints failed" : compact
        }
    }
}

struct HealthCheckOutcome: Equatable {
    let socksListening: Bool
    let externalIPResult: ExternalIPCheckResult?
}

actor HealthCheckService {
    private let portProbeService: PortProbeService
    private var externalIPCheckEnabled: Bool
    private var ipCheckURLs: [URL]
    private var cachedSession: URLSession?
    private var cachedSessionPort: Int?
    private var cachedSessionTimeout: TimeInterval?

    init(
        portProbeService: PortProbeService = PortProbeService(),
        ipCheckURL: URL = URL(string: ConnectionProfile.defaultExternalIPCheckURL)!,
        externalIPCheckEnabled: Bool = true
    ) {
        self.portProbeService = portProbeService
        self.ipCheckURLs = [ipCheckURL]
        self.externalIPCheckEnabled = externalIPCheckEnabled
    }

    func checkSocksPort(_ port: Int) async -> Bool {
        await portProbeService.isListening(port: port)
    }

    func updateExternalIPCheck(enabled: Bool, urlStrings: [String]) {
        externalIPCheckEnabled = enabled
        ipCheckURLs = Self.validatedExternalIPURLs(from: urlStrings)
    }

    func updateExternalIPCheck(enabled: Bool, urlString: String) {
        updateExternalIPCheck(enabled: enabled, urlStrings: [urlString])
    }

    static func validatedExternalIPURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    static func validatedExternalIPURLs(from rawValues: [String]) -> [URL] {
        rawValues.compactMap(validatedExternalIPURL(from:))
    }

    /// Fetches the public IP as seen through the local SOCKS proxy (SSH `-D`).
    func fetchExternalIPThroughSocks(localPort: Int, timeout: TimeInterval = 12) async -> String? {
        switch await fetchExternalIPThroughSocksDetailed(localPort: localPort, timeout: timeout) {
        case .success(let ip, _):
            return ip
        case .allFailed, .none:
            return nil
        }
    }

    /// Fetches public IP through SOCKS, trying endpoints in order until first success.
    func fetchExternalIPThroughSocksDetailed(localPort: Int, timeout: TimeInterval = 12) async -> ExternalIPCheckResult? {
        guard (1...65535).contains(localPort) else { return nil }
        guard externalIPCheckEnabled else { return nil }
        guard !ipCheckURLs.isEmpty else { return nil }

        let session = sessionForSocks(localPort: localPort, timeout: timeout)
        var failures: [ExternalIPFailureDetail] = []

        for endpoint in ipCheckURLs {
            do {
                let (data, response) = try await session.data(from: endpoint)
                guard let http = response as? HTTPURLResponse else {
                    failures.append(ExternalIPFailureDetail(endpoint: endpoint, reason: .unknown))
                    continue
                }
                guard (200...299).contains(http.statusCode) else {
                    failures.append(ExternalIPFailureDetail(endpoint: endpoint, reason: .httpStatus(http.statusCode)))
                    continue
                }
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else {
                    failures.append(ExternalIPFailureDetail(endpoint: endpoint, reason: .emptyBody))
                    continue
                }
                return .success(ip: text, endpoint: endpoint)
            } catch {
                failures.append(
                    ExternalIPFailureDetail(
                        endpoint: endpoint,
                        reason: classifyExternalIPError(error)
                    )
                )
            }
        }

        return .allFailed(failures)
    }

    /// SOCKS port must accept TCP; external IP is optional for degraded-but-up scenarios.
    func performHealthCheck(localPort: Int) async -> (socksListening: Bool, externalIP: String?) {
        let outcome = await performHealthCheckDetailed(localPort: localPort)
        let ip: String?
        switch outcome.externalIPResult {
        case .success(let value, _):
            ip = value
        case .allFailed, .none:
            ip = nil
        }
        return (outcome.socksListening, ip)
    }

    func performHealthCheckDetailed(localPort: Int) async -> HealthCheckOutcome {
        let socksListening = await checkSocksPort(localPort)
        guard socksListening else {
            return HealthCheckOutcome(socksListening: false, externalIPResult: nil)
        }
        let result = await fetchExternalIPThroughSocksDetailed(localPort: localPort)
        return HealthCheckOutcome(socksListening: true, externalIPResult: result)
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

    private func classifyExternalIPError(_ error: Error) -> ExternalIPFailureReason {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .dns
            case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
                return .tls
            case .cannotLoadFromNetwork, .networkConnectionLost, .notConnectedToInternet:
                return .proxyConnect
            default:
                return .unknown
            }
        }
        return .unknown
    }
}
