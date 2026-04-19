import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let statusBarController = StatusBarController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController.configure(with: appState)

        appState.$status
            .sink { [weak self] status in
                self?.statusBarController.updateStatus(status)
            }
            .store(in: &cancellables)
    }
}
