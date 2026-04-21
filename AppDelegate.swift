import AppKit
import Combine
import MacProxyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let statusBarController = StatusBarController()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController.configure(with: appState)
        updateApplicationIcon(for: appState.status)

        appState.$status
            .sink { [weak self] status in
                self?.statusBarController.updateStatus(status)
                self?.updateApplicationIcon(for: status)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.prepareForTermination()
    }

    private func updateApplicationIcon(for status: ProxyStatus) {
        let imageName = imageName(for: status)
        guard
            let imageURL = Bundle.module.url(forResource: imageName, withExtension: "png", subdirectory: "Images"),
            let image = NSImage(contentsOf: imageURL)
        else {
            return
        }
        NSApplication.shared.applicationIconImage = image
    }

    private func imageName(for status: ProxyStatus) -> String {
        switch status {
        case .connected:
            return "green-icon"
        case .degraded:
            return "yellow-icon"
        case .disconnected, .connecting, .reconnecting, .error:
            return "red-icon"
        }
    }
}
