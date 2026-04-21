import SwiftUI
import MacProxyCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var username: String = ""
    @State private var sshPort: Int = 22
    @State private var localSocksPort: Int = 1080
    @State private var useKeyAuthentication: Bool = false
    @State private var passwordEntry: String = ""
    @State private var externalIPCheckEnabled: Bool = true
    @State private var externalIPCheckURL: String = ConnectionProfile.defaultExternalIPCheckURL
    @State private var showDiscardConfirmation = false
    @State private var showDeletePasswordConfirmation = false

    private var validationErrors: [String] {
        var errors: [String] = []
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Host is required.")
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Username is required.")
        }
        if !(1...65535).contains(sshPort) {
            errors.append("SSH port must be between 1 and 65535.")
        }
        if !(1...65535).contains(localSocksPort) {
            errors.append("Local SOCKS port must be between 1 and 65535.")
        }
        if externalIPCheckEnabled {
            let rawURL = externalIPCheckURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(string: rawURL)
            let isValidHTTPS = url?.scheme?.lowercased() == "https" && (url?.host?.isEmpty == false)
            if !isValidHTTPS {
                errors.append("External IP check URL must be a valid HTTPS URL.")
            }
        }
        return errors
    }

    private var hasUnsavedChanges: Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIPURL = externalIPCheckURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return name != appState.profile.name ||
            trimmedHost != appState.profile.host ||
            trimmedUsername != appState.profile.username ||
            sshPort != appState.profile.sshPort ||
            localSocksPort != appState.profile.localSocksPort ||
            useKeyAuthentication != appState.profile.useKeyAuthentication ||
            externalIPCheckEnabled != appState.profile.externalIPCheckEnabled ||
            trimmedIPURL != appState.profile.externalIPCheckURL ||
            passwordEntry != appState.passwordEntry
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    closeAsCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)
                .accessibilityLabel("Close settings")

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            Form {
                TextField("Profile Name", text: $name)
                TextField("Host", text: $host)
                TextField("Username", text: $username)
                TextField("SSH Port", value: $sshPort, formatter: NumberFormatter())
                TextField("Local SOCKS Port", value: $localSocksPort, formatter: NumberFormatter())
                Toggle("Use SSH key authentication", isOn: $useKeyAuthentication)

                Divider()
                Toggle("Check external IP through proxy", isOn: $externalIPCheckEnabled)
                if externalIPCheckEnabled {
                    TextField("External IP check URL (HTTPS)", text: $externalIPCheckURL)
                        .disableAutocorrection(true)
                }

                if !validationErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error, systemImage: "xmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if !useKeyAuthentication {
                    Divider()
                    SecureField(passwordPlaceholder, text: $passwordEntry)
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
                            showDeletePasswordConfirmation = true
                        }
                        .disabled(!appState.hasKeychainPasswordForProfile)
                    }
                }

                HStack {
                    Spacer()
                    Button("Discard changes") {
                        closeAsCancel()
                    }
                    .keyboardShortcut(.escape)
                    Button("Save") {
                        saveSettings()
                        appState.isSettingsPresented = false
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!validationErrors.isEmpty)
                }
                .padding(.top)
            }
        }
        .frame(minWidth: 420)
        .onAppear {
            loadCurrentValues()
            appState.refreshKeychainPasswordState()
        }
        .confirmationDialog(
            "Discard all unsaved changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) {
                appState.resetProfile()
                appState.isSettingsPresented = false
            }
            Button("Keep editing", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove saved password from Keychain?",
            isPresented: $showDeletePasswordConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove password", role: .destructive) {
                appState.removeSavedPasswordFromKeychain()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to enter the SSH password again before the next password-based connection.")
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
        externalIPCheckEnabled = profile.externalIPCheckEnabled
        externalIPCheckURL = profile.externalIPCheckURL
        passwordEntry = appState.passwordEntry
    }

    private var passwordPlaceholder: String {
        if appState.hasKeychainPasswordForProfile {
            return "Password already in Keychain"
        }
        return "SSH password (saved to Keychain)"
    }

    private func closeAsCancel() {
        if hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            appState.resetProfile()
            appState.isSettingsPresented = false
        }
    }

    private func saveSettings() {
        appState.profile.name = name
        appState.profile.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.profile.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.profile.sshPort = sshPort
        appState.profile.localSocksPort = localSocksPort
        appState.profile.useKeyAuthentication = useKeyAuthentication
        appState.profile.externalIPCheckEnabled = externalIPCheckEnabled
        appState.profile.externalIPCheckURL = externalIPCheckURL.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.passwordEntry = passwordEntry
        appState.saveProfile()
    }
}
