import AppKit
import MacProxyCore

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var appState: AppState?

    private var statusMenuItem: NSMenuItem?
    private var statusDetailsMenuItem: NSMenuItem?
    private var connectMenuItem: NSMenuItem?
    private var disconnectMenuItem: NSMenuItem?

    func configure(with appState: AppState) {
        self.appState = appState
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }

        if let button = statusItem?.button {
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
            applyStatusAppearance(.disconnected, to: button)
        }
        statusItem?.menu = makeMenu()
        updateStatusMenuItems(for: appState.status)
        updateMenuItemAvailability(for: appState.status)
    }

    func updateStatus(_ status: ProxyStatus) {
        guard let button = statusItem?.button else { return }
        applyStatusAppearance(status, to: button)
        updateStatusMenuItems(for: status)
        updateMenuItemAvailability(for: status)
    }

    private func applyStatusAppearance(_ status: ProxyStatus, to button: NSStatusBarButton) {
        let symbolName: String
        let tint: NSColor
        let label: String

        switch status {
        case .disconnected:
            symbolName = "circle"
            tint = .tertiaryLabelColor
            label = "Off"
        case .connecting:
            symbolName = "circle.dotted"
            tint = .systemYellow
            label = "…"
        case .reconnecting:
            symbolName = "arrow.clockwise.circle.fill"
            tint = .systemOrange
            label = "↻"
        case .connected:
            symbolName = "circle.fill"
            tint = .systemGreen
            label = "On"
        case .degraded:
            symbolName = "exclamationmark.circle.fill"
            tint = .systemOrange
            label = "!"
        case .error:
            symbolName = "xmark.circle.fill"
            tint = .systemRed
            label = "Err"
        }

        let isDarkMode = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let finalTint: NSColor = isDarkMode ? .white : tint

        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        var accessibilityDescription = "Proxy status: \(status.title)"
        if let details = status.details {
            accessibilityDescription += ". \(details)"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)?
            .withSymbolConfiguration(config)
        button.image = image
        button.contentTintColor = finalTint
        button.title = " \(label)"
        if isDarkMode {
            button.attributedTitle = NSAttributedString(
                string: " \(label)",
                attributes: [.foregroundColor: NSColor.white]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: " \(label)")
        }

        var tip = "MacProxyUI — \(status.title)"
        if let details = status.details {
            tip += "\n\(details)"
        }
        button.toolTip = tip
    }

    private func updateMenuItemAvailability(for status: ProxyStatus) {
        let canConnect: Bool
        let canDisconnect: Bool

        switch status {
        case .connecting, .reconnecting, .connected, .degraded:
            canConnect = false
            canDisconnect = true
        case .disconnected:
            canConnect = true
            canDisconnect = false
        case .error:
            canConnect = true
            canDisconnect = true
        }

        connectMenuItem?.isEnabled = canConnect
        disconnectMenuItem?.isEnabled = canDisconnect
    }

    private func updateStatusMenuItems(for status: ProxyStatus) {
        statusMenuItem?.title = "Status: \(status.title)"

        if let details = status.details {
            statusDetailsMenuItem?.title = details.replacingOccurrences(of: "\n", with: " ")
            statusDetailsMenuItem?.isHidden = false
        } else {
            statusDetailsMenuItem?.title = ""
            statusDetailsMenuItem?.isHidden = true
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusMenuItem = status
        menu.addItem(status)

        let details = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        details.isEnabled = false
        details.isHidden = true
        statusDetailsMenuItem = details
        menu.addItem(details)

        menu.addItem(NSMenuItem.separator())

        let connect = NSMenuItem(title: "Connect", action: #selector(connect), keyEquivalent: "")
        connect.target = self
        connectMenuItem = connect
        menu.addItem(connect)

        let disconnect = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "")
        disconnect.target = self
        disconnectMenuItem = disconnect
        menu.addItem(disconnect)

        menu.addItem(NSMenuItem.separator())

        let showWindow = NSMenuItem(title: "Show Window", action: #selector(showWindow), keyEquivalent: "")
        showWindow.target = self
        menu.addItem(showWindow)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit MacProxyUI", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func connect() {
        appState?.connect()
    }

    @objc private func disconnect() {
        appState?.disconnect()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        appState?.isSettingsPresented = true
        bringWindowToFront()
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowToFront()
    }

    private func bringWindowToFront() {
        let windows = NSApp.windows
        if let key = windows.first(where: { $0.isKeyWindow }) {
            key.makeKeyAndOrderFront(nil)
        } else if let main = windows.first(where: { $0.isMainWindow }) {
            main.makeKeyAndOrderFront(nil)
        } else {
            windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
