import Foundation

/// Schedules a single delayed reconnect on the main run loop.
final class ReconnectCoordinator {
    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 7) {
        self.interval = interval
    }

    func scheduleReconnect(action: @escaping @MainActor () -> Void) {
        let work = { [weak self] in
            guard let self else { return }
            self.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: false) { _ in
                Task { @MainActor in
                    action()
                }
            }
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func invalidate() {
        let work = { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
