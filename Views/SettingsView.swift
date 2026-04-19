import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            TextField("Profile Name", text: $appState.profile.name)
            TextField("Host", text: $appState.profile.host)
            TextField("Username", text: $appState.profile.username)
            TextField("SSH Port", value: $appState.profile.sshPort, formatter: NumberFormatter())
            TextField("Local SOCKS Port", value: $appState.profile.localSocksPort, formatter: NumberFormatter())
            Toggle("Use SSH key authentication", isOn: $appState.profile.useKeyAuthentication)

            if !appState.profile.useKeyAuthentication {
                Divider()
                SecureField("SSH password (saved to Keychain)", text: $appState.passwordEntry)
                    .textContentType(.password)

                HStack(alignment: .top) {
                    Text(
                        appState.hasKeychainPasswordForProfile
                            ? "A password for this user@host:port is stored in Keychain. Enter a new password here to replace it on Connect."
                            : "Enter your SSH password before Connect. It is saved to Keychain and reused for reconnects."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Remove from Keychain") {
                        appState.removeSavedPasswordFromKeychain()
                    }
                    .disabled(!appState.hasKeychainPasswordForProfile)
                }
            }
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            appState.refreshKeychainPasswordState()
        }
        .onChange(of: appState.profile) { _ in
            appState.refreshKeychainPasswordState()
        }
    }
}
