import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var username: String = ""
    @State private var sshPort: Int = 22
    @State private var localSocksPort: Int = 1080
    @State private var useKeyAuthentication: Bool = false
    @State private var passwordEntry: String = ""

    var body: some View {
        Form {
            TextField("Profile Name", text: $name)
            TextField("Host", text: $host)
            TextField("Username", text: $username)
            TextField("SSH Port", value: $sshPort, formatter: NumberFormatter())
            TextField("Local SOCKS Port", value: $localSocksPort, formatter: NumberFormatter())
            Toggle("Use SSH key authentication", isOn: $useKeyAuthentication)

            if !useKeyAuthentication {
                Divider()
                SecureField("SSH password (saved to Keychain)", text: $passwordEntry)
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

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.resetProfile()
                    appState.isSettingsPresented = false
                }
                .keyboardShortcut(.escape)
                Button("Save") {
                    saveSettings()
                    appState.isSettingsPresented = false
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(minWidth: 420)
        .onAppear {
            loadCurrentValues()
            appState.refreshKeychainPasswordState()
        }
    }

    private func loadCurrentValues() {
        let profile = appState.profile
        name = profile.name
        host = profile.host
        username = profile.username
        sshPort = profile.sshPort
        localSocksPort = profile.localSocksPort
        useKeyAuthentication = profile.useKeyAuthentication
        passwordEntry = appState.passwordEntry
    }

    private func saveSettings() {
        appState.profile.name = name
        appState.profile.host = host
        appState.profile.username = username
        appState.profile.sshPort = sshPort
        appState.profile.localSocksPort = localSocksPort
        appState.profile.useKeyAuthentication = useKeyAuthentication
        appState.passwordEntry = passwordEntry
        appState.saveProfile()
    }
}
