import Foundation
import os
import AppKit
import SwiftUI

public struct MainScreenEvent: Identifiable, Equatable {
    public enum Source: Equatable {
        case system
        case status
        case diagnostics
    }

    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let source: Source

    public var timestampLabel: String {
        MainScreenEvent.timestampFormatter.string(from: timestamp)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var profile = ConnectionProfile()
    @Published public var status: ProxyStatus = .disconnected {
        didSet {
            guard status != oldValue else { return }
            appendStatusTransition(from: oldValue, to: status)
        }
    }
    @Published public var externalIP: String = "-"
    @Published public private(set) var mainScreenEvents: [MainScreenEvent] = []

    /// Drives the Settings sheet from both the main window and the menu bar.
    @Published public var isSettingsPresented = false

    /// Ephemeral field for typing a password; saved to Keychain on Connect when non-empty.
    @Published public var passwordEntry: String = ""

    private var savedProfile: ConnectionProfile?

    /// Whether Keychain already has a password for the current host/port/username.
    @Published public private(set) var hasKeychainPasswordForProfile = false

    private let sshService: SshProcessService
    private let healthCheckService: HealthCheckService
    private let reconnectCoordinator: ReconnectCoordinator
    private let keychainService: KeychainService
    private let profileStore: ProfileStore
    private let diagnosticsStore: DiagnosticsStore
    private let reconnectPolicy: ReconnectPolicy
    private let logger = Logger(subsystem: "com.macproxyui.app", category: "ssh")
    private let maxMainScreenEvents = 200

    private var manuallyDisconnected = false
    private var connectProbeTask: Task<Void, Never>?
    private var healthMonitorTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    private let healthCheckInterval: Duration = .seconds(45)
    private let initialSocksProbeInterval: Duration = .milliseconds(250)
    private let initialSocksProbeTimeout: Duration = .seconds(4)

    init(
        sshService: SshProcessService,
        healthCheckService: HealthCheckService,
        reconnectCoordinator: ReconnectCoordinator,
        keychainService: KeychainService,
        profileStore: ProfileStore? = nil,
        diagnosticsStore: DiagnosticsStore,
        reconnectPolicy: ReconnectPolicy
    ) {
        let resolvedProfileStore = profileStore ?? ProfileStore(secureStore: keychainService)
        self.sshService = sshService
        self.healthCheckService = healthCheckService
        self.reconnectCoordinator = reconnectCoordinator
        self.keychainService = keychainService
        self.profileStore = resolvedProfileStore
        self.diagnosticsStore = diagnosticsStore
        self.reconnectPolicy = reconnectPolicy

        sshService.onTermination = { [weak self] info in
            Task { @MainActor in
                self?.handleTermination(info: info)
            }
        }
        sshService.onStderrLine = { [weak self] line in
            self?.logger.info("ssh stderr: \(line, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.diagnosticsStore.append(line)
                self?.appendEvent(message: line, source: .diagnostics)
            }
        }

        refreshKeychainPasswordState()
        loadProfile()
        appendEvent(message: launchSettingsSummary(), source: .system)
    }

    public convenience init() {
        let keychain = KeychainService()
        self.init(
            sshService: SshProcessService(),
            healthCheckService: HealthCheckService(),
            reconnectCoordinator: ReconnectCoordinator(),
            keychainService: keychain,
            profileStore: nil,
            diagnosticsStore: DiagnosticsStore(),
            reconnectPolicy: ReconnectPolicy()
        )
    }

    private func loadProfile() {
        if let loaded = profileStore.load() {
            profile = loaded
            savedProfile = loaded
        }
        refreshKeychainPasswordState()
        Task {
            await healthCheckService.updateExternalIPCheck(
                enabled: profile.externalIPCheckEnabled,
                urlString: profile.externalIPCheckURL
            )
        }
    }

    public func saveProfile() {
        let previousProfile = savedProfile ?? ConnectionProfile()
        profileStore.save(profile)
        savedProfile = profile
        Task {
            await healthCheckService.updateExternalIPCheck(
                enabled: profile.externalIPCheckEnabled,
                urlString: profile.externalIPCheckURL
            )
        }
        appendEvent(
            message: "Settings saved: \(profileSummary(profile)) (changed: \(profileDiffSummary(from: previousProfile, to: profile))).",
            source: .system
        )
    }

    public func resetProfile() {
        profile = savedProfile ?? ConnectionProfile()
        passwordEntry = ""
    }

    public func refreshKeychainPasswordState() {
        let account = KeychainService.accountIdentifier(for: profile)
        hasKeychainPasswordForProfile = keychainService.hasPassword(account: account)
    }

    public func removeSavedPasswordFromKeychain() {
        let account = KeychainService.accountIdentifier(for: profile)
        do {
            try keychainService.deletePassword(account: account)
            refreshKeychainPasswordState()
        } catch {
            status = .error("Could not remove Keychain item: \(error.localizedDescription)")
        }
    }

    public func connect() {
        appendEvent(
            message: "Connect requested: destination=\(profile.destination), sshPort=\(profile.sshPort), socksPort=\(profile.localSocksPort), auth=\(profile.useKeyAuthentication ? "key" : "password"), ipCheck=\(profile.externalIPCheckEnabled ? "on" : "off").",
            source: .system
        )
        guard profile.isValid else {
            status = .error("Please fill host, username, and ports.")
            return
        }
        guard profile.hasValidExternalIPCheckURL else {
            status = .error("External IP check URL must be a valid HTTPS URL.")
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
                    "Password login requires AskpassHelper inside the app bundle. Reinstall MacProxyUI or rebuild the full app package."
                )
                return
            }

            sshEnvironment = SshAskpassConfiguration.sshEnvironment(helperExecutable: askpassURL, keychainAccount: account)
        }

        manuallyDisconnected = false
        reconnectAttempt = 0
        reconnectCoordinator.invalidate()
        status = .connecting
        externalIP = "-"
        connectProbeTask?.cancel()
        healthMonitorTask?.cancel()
        healthMonitorTask = nil

        do {
            try sshService.start(profile: profile, environment: sshEnvironment)
            appendEvent(
                message: "SSH process started (pid active), waiting for local SOCKS \(profile.localSocksPort) readiness.",
                source: .system
            )
            connectProbeTask = Task { [weak self] in
                guard let self else { return }
                await self.healthCheckService.updateExternalIPCheck(
                    enabled: self.profile.externalIPCheckEnabled,
                    urlString: self.profile.externalIPCheckURL
                )
                await self.finishStartupHealthCheck()
            }
        } catch {
            status = .error("Failed to start ssh: \(error.localizedDescription)")
        }
    }

    public func disconnect() {
        manuallyDisconnected = true
        reconnectAttempt = 0
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

    public func prepareForTermination() {
        manuallyDisconnected = true
        reconnectAttempt = 0
        reconnectCoordinator.invalidate()
        connectProbeTask?.cancel()
        connectProbeTask = nil
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        externalIP = "-"
        sshService.stop()
        status = .disconnected
    }

    public var canConnectFromUI: Bool {
        guard !sshService.isRunning else { return false }
        switch status {
        case .connecting, .reconnecting, .connected, .degraded:
            return false
        case .disconnected, .error:
            return true
        }
    }

    public var canDisconnectFromUI: Bool {
        sshService.isRunning || status != .disconnected
    }

    public var needsInitialSetup: Bool {
        !profile.isValid
    }

    public func copyDiagnosticsToPasteboard() {
        let text = diagnosticsStore.render(status: status, profile: profile, externalIP: externalIP)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
                        if self.profile.externalIPCheckEnabled {
                            self.status = .degraded("External IP check through SOCKS failed (proxy may be partial).")
                        } else {
                            self.status = .connected
                        }
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
        appendEvent(
            message: "SOCKS readiness check passed on localhost:\(localPort); validating external route.",
            source: .system
        )

        let externalIP = await healthCheckService.fetchExternalIPThroughSocks(localPort: localPort)
        guard !Task.isCancelled else { return }

        if profile.externalIPCheckEnabled, let externalIP {
            self.externalIP = externalIP
            status = .connected
            appendEvent(
                message: "Tunnel established: SOCKS localhost:\(localPort), externalIP=\(externalIP), mode=full.",
                source: .system
            )
        } else if profile.externalIPCheckEnabled {
            self.externalIP = "-"
            status = .degraded("SOCKS port is open, but the external IP check via proxy failed.")
            appendEvent(
                message: "Tunnel partial: SOCKS localhost:\(localPort) is up but external IP check failed.",
                source: .system
            )
        } else {
            self.externalIP = "-"
            status = .connected
            appendEvent(
                message: "Tunnel established: SOCKS localhost:\(localPort), external IP check disabled by settings.",
                source: .system
            )
        }

        reconnectAttempt = 0
        startHealthMonitoring()
    }

    private func handleHealthCheckFailure() {
        externalIP = "-"
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        connectProbeTask?.cancel()
        connectProbeTask = nil

        scheduleReconnect(reason: "SOCKS proxy stopped responding.")

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
            reconnectAttempt = 0
            return
        }

        let message = SshProcessService.humanReadableMessage(for: info)
        guard reconnectPolicy.shouldRetry(parsedFailure: info.parsedFailure) else {
            switch info.parsedFailure {
            case .hostKeyVerificationFailed:
                status = .error("\(message) Auto-reconnect stopped. Confirm and trust the host key, then connect again.")
            case .authenticationFailed, .permissionDenied:
                status = .error("\(message) Auto-reconnect stopped. Update credentials in Settings and reconnect.")
            default:
                status = .error("\(message) Auto-reconnect stopped.")
            }
            reconnectAttempt = 0
            return
        }

        let retryReason: String
        if let code = info.exitCodeOrSignal {
            retryReason = "\(message) (code \(code))."
        } else {
            retryReason = message
        }
        scheduleReconnect(reason: retryReason)
    }

    private func scheduleReconnect(reason: String) {
        reconnectCoordinator.invalidate()
        if reconnectAttempt >= reconnectPolicy.maxAttempts {
            status = .error("\(reason) Reconnect attempts exhausted. Open Settings, fix configuration, then reconnect.")
            reconnectAttempt = 0
            return
        }

        reconnectAttempt += 1
        let delay = reconnectPolicy.delaySeconds(forAttempt: reconnectAttempt)
        reconnectCoordinator.scheduleReconnect(
            after: delay,
            onTick: { [weak self] remaining in
                guard let self else { return }
                self.status = .reconnecting(
                    remainingSeconds: remaining,
                    reason: "\(reason) Attempt \(self.reconnectAttempt) of \(self.reconnectPolicy.maxAttempts)."
                )
            },
            action: { [weak self] in
                self?.connect()
            }
        )
    }

    private func appendStatusTransition(from previous: ProxyStatus, to next: ProxyStatus) {
        if case .reconnecting = previous, case .reconnecting = next {
            return
        }

        let message: String
        switch next {
        case .connecting:
            message = "Status -> Connecting (destination=\(profile.destination), sshPort=\(profile.sshPort), socksPort=\(profile.localSocksPort))."
        case .connected:
            message = "Status -> Connected (destination=\(profile.destination), socksPort=\(profile.localSocksPort), externalIP=\(externalIP))."
        default:
            if let details = next.details {
                let compactDetails = details.replacingOccurrences(of: "\n", with: " ")
                message = "\(next.title): \(compactDetails)"
            } else {
                message = next.title
            }
        }
        appendEvent(message: message, source: .status)
    }

    private func appendEvent(message: String, source: MainScreenEvent.Source) {
        let event = MainScreenEvent(timestamp: Date(), message: message, source: source)
        mainScreenEvents.insert(event, at: 0)
        if mainScreenEvents.count > maxMainScreenEvents {
            mainScreenEvents.removeLast(mainScreenEvents.count - maxMainScreenEvents)
        }
    }

    private func launchSettingsSummary() -> String {
        let profileDescription = profileSummary(profile)
        let keychainState = hasKeychainPasswordForProfile ? "keychainPassword=present" : "keychainPassword=missing"
        return "Launched: loaded settings { \(profileDescription), \(keychainState) }."
    }

    private func profileSummary(_ profile: ConnectionProfile) -> String {
        let ipCheck = profile.externalIPCheckEnabled ? "on" : "off"
        let auth = profile.useKeyAuthentication ? "key" : "password"
        let label = profile.name.isEmpty ? "Default" : profile.name
        return "name=\(label), destination=\(profile.destination), sshPort=\(profile.sshPort), socksPort=\(profile.localSocksPort), auth=\(auth), ipCheck=\(ipCheck)"
    }

    private func profileDiffSummary(from old: ConnectionProfile, to new: ConnectionProfile) -> String {
        var changed: [String] = []
        if old.name != new.name { changed.append("name") }
        if old.host != new.host { changed.append("host") }
        if old.username != new.username { changed.append("username") }
        if old.sshPort != new.sshPort { changed.append("sshPort") }
        if old.localSocksPort != new.localSocksPort { changed.append("socksPort") }
        if old.useKeyAuthentication != new.useKeyAuthentication { changed.append("authMode") }
        if old.externalIPCheckEnabled != new.externalIPCheckEnabled { changed.append("ipCheckEnabled") }
        if old.externalIPCheckURL != new.externalIPCheckURL { changed.append("ipCheckURL") }
        return changed.isEmpty ? "none" : changed.joined(separator: ",")
    }
}
