import Foundation

/// Schedules reconnect attempts and provides countdown ticks.
final class ReconnectCoordinator {
    private var reconnectTask: Task<Void, Never>?

    func scheduleReconnect(
        after delaySeconds: Int,
        onTick: (@MainActor (Int) -> Void)? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let scheduleWork = { [weak self] in
            guard let self else { return }
            self.invalidate()
            self.reconnectTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let clampedDelay = max(1, delaySeconds)
                for second in stride(from: clampedDelay, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    onTick?(second)
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                action()
                self.reconnectTask = nil
            }
        }

        if Thread.isMainThread {
            scheduleWork()
        } else {
            DispatchQueue.main.async(execute: scheduleWork)
        }
    }

    func invalidate() {
        let invalidateWork = { [weak self] in
            self?.reconnectTask?.cancel()
            self?.reconnectTask = nil
        }
        if Thread.isMainThread {
            invalidateWork()
        } else {
            DispatchQueue.main.async(execute: invalidateWork)
        }
    }
}
