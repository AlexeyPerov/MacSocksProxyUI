import Foundation
import SwiftUI

private enum StorageKey {
    static let profile = "connectionProfile"
}

@MainActor
final class AppState: ObservableObject {
    @Published var profile = ConnectionProfile()
    @Published var status: ProxyStatus = .disconnected
    @Published var statusMessage: String = ""
    @Published var externalIP: String = "-"

    /// Drives the Settings sheet from both the main window and the menu bar.
    @Published var isSettingsPresented = false

    /// Ephemeral field for typing a password; saved to Keychain on Connect when non-empty.
    @Published var passwordEntry: String = ""

    private var savedProfile: ConnectionProfile?

    /// Whether Keychain already has a password for the current host/port/username.
    @Published private(set) var hasKeychainPasswordForProfile = false

    private let sshService: SshProcessService
    private let healthCheckService: HealthCheckService
    private let reconnectCoordinator: ReconnectCoordinator
    private let keychainService: KeychainService

    private var manuallyDisconnected = false
    private var connectProbeTask: Task<Void, Never>?
    private var healthMonitorTask: Task<Void, Never>?

    private let healthCheckInterval: Duration = .seconds(45)
    private let initialSocksProbeInterval: Duration = .milliseconds(250)
    private let initialSocksProbeTimeout: Duration = .seconds(4)

    init(
        sshService: SshProcessService = SshProcessService(),
        healthCheckService: HealthCheckService = HealthCheckService(),
        reconnectCoordinator: ReconnectCoordinator = ReconnectCoordinator(),
        keychainService: KeychainService = KeychainService()
    ) {
        self.sshService = sshService
        self.healthCheckService = healthCheckService
        self.reconnectCoordinator = reconnectCoordinator
        self.keychainService = keychainService

        sshService.onTermination = { [weak self] info in
            Task { @MainActor in
                self?.handleTermination(info: info)
            }
        }

        refreshKeychainPasswordState()
        loadProfile()
    }

    private func loadProfile() {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.profile),
              let loaded = try? JSONDecoder().decode(ConnectionProfile.self, from: data) else {
            return
        }
        profile = loaded
        savedProfile = loaded
    }

    func saveProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: StorageKey.profile)
        savedProfile = profile
    }

    func resetProfile() {
        profile = savedProfile ?? ConnectionProfile()
        passwordEntry = ""
    }

    func refreshKeychainPasswordState() {
        let account = KeychainService.accountIdentifier(for: profile)
        hasKeychainPasswordForProfile = keychainService.hasPassword(account: account)
    }

    func removeSavedPasswordFromKeychain() {
        let account = KeychainService.accountIdentifier(for: profile)
        do {
            try keychainService.deletePassword(account: account)
            refreshKeychainPasswordState()
        } catch {
            status = .error("Could not remove Keychain item: \(error.localizedDescription)")
        }
    }

    func connect() {
        guard profile.isValid else {
            status = .error("Please fill host, username, and ports.")
            return
        }

        let sshEnvironment: [String: String]
        if profile.useKeyAuthentication {
            sshEnvironment = [:]
        } else {
            let account = KeychainService.accountIdentifier(for: profile)
            do {
                let trimmed = passwordEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try keychainService.savePassword(trimmed, account: account)
                    passwordEntry = ""
                    refreshKeychainPasswordState()
                }
                guard keychainService.hasPassword(account: account) else {
                    status = .error(
                        "SSH password is required. Enter it below; it is stored only in Keychain (never in project files)."
                    )
                    return
                }
            } catch {
                status = .error("Keychain: \(error.localizedDescription)")
                return
            }

            guard let askpassURL = SshAskpassConfiguration.resolveHelperExecutableURL() else {
                status = .error(
                    "Could not find AskpassHelper next to MacProxyUI. Rebuild so AskpassHelper is produced alongside the app."
                )
                return
            }

            sshEnvironment = SshAskpassConfiguration.sshEnvironment(helperExecutable: askpassURL, keychainAccount: account)
        }

        manuallyDisconnected = false
        status = .connecting
        externalIP = "-"
        connectProbeTask?.cancel()
        healthMonitorTask?.cancel()
        healthMonitorTask = nil

        do {
            try sshService.start(profile: profile, environment: sshEnvironment)
            connectProbeTask = Task { [weak self] in
                guard let self else { return }
                await self.finishStartupHealthCheck()
            }
        } catch {
            status = .error("Failed to start ssh: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        manuallyDisconnected = true
        reconnectCoordinator.invalidate()
        connectProbeTask?.cancel()
        connectProbeTask = nil
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        externalIP = "-"
        Task.detached { [sshService] in
            sshService.stop()
            await MainActor.run { [weak self] in
                self?.status = .disconnected
            }
        }
    }

    private func startHealthMonitoring() {
        healthMonitorTask?.cancel()
        healthMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.healthCheckInterval)
                guard !Task.isCancelled else { break }

                let port = await MainActor.run { self.profile.localSocksPort }
                let (socksListening, ip) = await self.healthCheckService.performHealthCheck(localPort: port)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.sshService.isRunning, !self.manuallyDisconnected else { return }

                    if !socksListening {
                        self.handleHealthCheckFailure()
                        return
                    }

                    if let ip {
                        self.externalIP = ip
                        if case .degraded = self.status {
                            self.status = .connected
                        }
                    } else {
                        self.externalIP = "-"
                        self.status = .degraded("External IP check through SOCKS failed (proxy may be partial).")
                    }
                }
            }
        }
    }

    private func finishStartupHealthCheck() async {
        let localPort = profile.localSocksPort
        let start = ContinuousClock.now
        var socksListening = false

        while !Task.isCancelled, sshService.isRunning {
            socksListening = await healthCheckService.checkSocksPort(localPort)
            if socksListening {
                break
            }

            if start.duration(to: ContinuousClock.now) >= initialSocksProbeTimeout {
                break
            }

            try? await Task.sleep(for: initialSocksProbeInterval)
        }

        guard !Task.isCancelled else { return }

        guard sshService.isRunning else {
            status = .error("SSH exited before the local SOCKS proxy finished starting.")
            return
        }

        guard socksListening else {
            status = .degraded("SSH started, but the local SOCKS proxy did not become ready in time.")
            return
        }

        let externalIP = await healthCheckService.fetchExternalIPThroughSocks(localPort: localPort)
        guard !Task.isCancelled else { return }

        if let externalIP {
            self.externalIP = externalIP
            status = .connected
        } else {
            self.externalIP = "-"
            status = .degraded("SOCKS port is open, but the external IP check via proxy failed.")
        }

        startHealthMonitoring()
    }

    private func handleHealthCheckFailure() {
        externalIP = "-"
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        connectProbeTask?.cancel()
        connectProbeTask = nil

        status = .error("SOCKS proxy stopped responding. Reconnecting...")
        reconnectCoordinator.invalidate()
        reconnectCoordinator.scheduleReconnect { [weak self] in
            self?.connect()
        }

        Task.detached { [sshService] in
            sshService.stop()
        }
    }

    private func handleTermination(info: SshTerminationInfo) {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        connectProbeTask?.cancel()
        connectProbeTask = nil
        externalIP = "-"

        if manuallyDisconnected {
            status = .disconnected
            return
        }

        let message = SshProcessService.humanReadableMessage(for: info)
        if let code = info.exitCodeOrSignal {
            status = .error("\(message) (details: code \(code)). Reconnecting...")
        } else {
            status = .error("\(message). Reconnecting...")
        }
        reconnectCoordinator.scheduleReconnect { [weak self] in
            self?.connect()
        }
    }
}
