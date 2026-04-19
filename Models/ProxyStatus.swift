import Foundation

enum ProxyStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case degraded(String)
    case error(String)

    var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .degraded:
            return "Degraded"
        case .error:
            return "Error"
        }
    }

    var details: String? {
        switch self {
        case .degraded(let message), .error(let message):
            return message
        default:
            return nil
        }
    }
}
