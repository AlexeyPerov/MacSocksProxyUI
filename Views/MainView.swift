import SwiftUI
import MacProxyCore

struct MainView: View {
    static let minimumWindowWidth: CGFloat = 620
    static let minimumWindowHeight: CGFloat = 760

    @ObservedObject var appState: AppState

    private var primaryButtonTitle: String {
        switch appState.status {
        case .disconnected, .error:
            return "Connect"
        case .connecting, .reconnecting, .connected, .degraded:
            return "Disconnect"
        }
    }

    private var primaryButtonIsEnabled: Bool {
        switch appState.status {
        case .disconnected, .error:
            return appState.canConnectFromUI
        case .connecting, .reconnecting, .connected, .degraded:
            return appState.canDisconnectFromUI
        }
    }

    private func handlePrimaryButtonTap() {
        switch appState.status {
        case .disconnected, .error:
            appState.connect()
        case .connecting, .reconnecting, .connected, .degraded:
            appState.disconnect()
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Text("Status: \(appState.status.title.lowercased())")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Proxy status")
                    .accessibilityValue(appState.status.title)

                Button {
                    appState.isSettingsPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.primary, lineWidth: 1.75)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: [.command])
                .accessibilityLabel("Open settings")
            }
            .padding(.top, 6)

            Text("External IP (via SOCKS): \(appState.externalIP)")
                .font(.system(size: 16, weight: .regular, design: .default))
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)

            if appState.needsInitialSetup {
                Text("Open Settings to add host, username, and port values.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: handlePrimaryButtonTap) {
                Text(primaryButtonTitle)
                    .font(.system(size: 33, weight: .medium, design: .default))
                    .frame(width: 210, height: 210)
                    .overlay(
                        Circle()
                            .stroke(.primary, lineWidth: 3)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!primaryButtonIsEnabled)
            .accessibilityLabel("\(primaryButtonTitle) proxy")

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 28)
                .stroke(.primary, lineWidth: 2.5)
                .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290)
                .overlay(alignment: .topLeading) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.mainScreenEvents) { event in
                                Text("[\(event.timestampLabel)] \(event.message)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if appState.mainScreenEvents.isEmpty {
                                Text("No events yet")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .padding(18)
                    }
                }
        }
        .padding(20)
        .frame(minWidth: Self.minimumWindowWidth, minHeight: Self.minimumWindowHeight)
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
                .frame(minWidth: 480, minHeight: 400)
        }
    }
}
