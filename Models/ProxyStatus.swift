import Foundation

public enum ProxyStatus: Equatable {
    case disconnected
    case connecting
    case reconnecting(remainingSeconds: Int, reason: String)
    case connected
    case degraded(String)
    case error(String)

    public var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return "Reconnecting"
        case .connected:
            return "Connected"
        case .degraded:
            return "Degraded"
        case .error:
            return "Error"
        }
    }

    public var details: String? {
        switch self {
        case .reconnecting(let remainingSeconds, let reason):
            return "\(reason) Retrying in \(remainingSeconds)s."
        case .degraded(let message), .error(let message):
            return message
        default:
            return nil
        }
    }
}
