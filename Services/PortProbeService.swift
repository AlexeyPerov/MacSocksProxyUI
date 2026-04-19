import Foundation
import Network

/// TCP connect probe to verify a local SOCKS listener is accepting connections.
final class PortProbeService {
    func isListening(host: String = "127.0.0.1", port: Int, timeout: TimeInterval = 1.0) async -> Bool {
        guard (1...65535).contains(port) else { return false }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)

        return await withCheckedContinuation { continuation in
            final class ResumeOnce: @unchecked Sendable {
                private let lock = NSLock()
                private var hasResumed = false
                private let continuation: CheckedContinuation<Bool, Never>

                init(_ continuation: CheckedContinuation<Bool, Never>) {
                    self.continuation = continuation
                }

                func resume(returning value: Bool) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: value)
                }
            }

            let resumeOnce = ResumeOnce(continuation)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resumeOnce.resume(returning: true)
                    connection.cancel()
                case .failed:
                    connection.cancel()
                    resumeOnce.resume(returning: false)
                case .cancelled:
                    resumeOnce.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
            }
        }
    }
}
