import SwiftUI

struct MainView: View {
    @ObservedObject var appState: AppState

    private var canConnect: Bool {
        switch appState.status {
        case .connecting, .connected:
            return false
        default:
            return true
        }
    }

    private var canDisconnect: Bool {
        appState.status != .disconnected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacProxyUI")
                .font(.title2.bold())

            Text("Status: \(appState.status.title)")
            if let details = appState.status.details {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("External IP (via SOCKS)")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(appState.externalIP)
                    .textSelection(.enabled)
                    .monospaced()
            }
            .font(.footnote)

            HStack(spacing: 12) {
                Button("Connect") {
                    appState.connect()
                }
                .disabled(!canConnect)

                Button("Disconnect") {
                    appState.disconnect()
                }
                .disabled(!canDisconnect)

                Spacer(minLength: 8)

                Button("Settings…") {
                    appState.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
                .frame(minWidth: 480, minHeight: 400)
        }
    }
}
