import SwiftUI
import MacProxyCore

struct MainView: View {
    @ObservedObject var appState: AppState

    private var canConnect: Bool {
        appState.canConnectFromUI
    }

    private var canDisconnect: Bool {
        appState.canDisconnectFromUI
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MacProxyUI")
                .font(.title2.bold())

            Text("Status: \(appState.status.title)")
                .accessibilityLabel("Proxy status")
                .accessibilityValue(appState.status.title)
            if let details = appState.status.details {
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if appState.needsInitialSetup {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Connection profile is incomplete.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Open Settings to add host, username, and port values before connecting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        appState.isSettingsPresented = true
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
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
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                Button("Connect") {
                    appState.connect()
                }
                .disabled(!canConnect)
                .accessibilityLabel("Connect proxy")
                .accessibilityHint("Starts the SSH SOCKS tunnel.")

                Button("Disconnect") {
                    appState.disconnect()
                }
                .disabled(!canDisconnect)
                .accessibilityLabel("Disconnect proxy")
                .accessibilityHint("Stops the SSH SOCKS tunnel.")

                Button("Copy Diagnostics") {
                    appState.copyDiagnosticsToPasteboard()
                }
                .accessibilityLabel("Copy diagnostics")
                .accessibilityHint("Copies current status and recent SSH stderr to the clipboard.")

                Spacer(minLength: 8)

                Button("Settings…") {
                    appState.isSettingsPresented = true
                }
                .keyboardShortcut(",", modifiers: [.command])
                .accessibilityLabel("Open settings")
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
