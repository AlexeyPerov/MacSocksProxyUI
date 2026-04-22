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
    private var wakeRefreshTask: Task<Void, Never>?
    private var reconnectAttempt = 0

    private let healthCheckIntervalConnected: Duration = .seconds(45)
    private let healthCheckIntervalDegraded: Duration = .seconds(15)
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
                urlStrings: profile.normalizedExternalIPCheckURLs
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
                urlStrings: profile.normalizedExternalIPCheckURLs
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
            status = .error("External IP check URL list must contain valid HTTPS URLs.")
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
                    urlStrings: self.profile.normalizedExternalIPCheckURLs
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
        wakeRefreshTask?.cancel()
        wakeRefreshTask = nil
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
        wakeRefreshTask?.cancel()
        wakeRefreshTask = nil
        externalIP = "-"
        sshService.stop()
        status = .disconnected
    }

    public func handleSystemDidWake() {
        guard sshService.isRunning, !manuallyDisconnected else { return }

        wakeRefreshTask?.cancel()
        appendEvent(message: "macOS wake detected. Running immediate tunnel health refresh.", source: .system)
        wakeRefreshTask = Task { [weak self] in
            guard let self else { return }

            let localPort = await MainActor.run { self.profile.localSocksPort }
            let outcome = await self.healthCheckService.performHealthCheckDetailed(localPort: localPort)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.sshService.isRunning, !self.manuallyDisconnected else { return }

                let wakeCheckFailed = self.didHealthCheckFailForWake(outcome)

                if wakeCheckFailed {
                    self.appendEvent(
                        message: "Wake refresh failed. Forcing reconnect attempt.",
                        source: .system
                    )
                    self.handleHealthCheckFailure(reason: "Wake refresh failed.")
                    return
                }

                self.applySuccessfulHealthCheckOutcome(outcome, context: "wake")
                self.startHealthMonitoring()
            }
        }
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
                let interval = await MainActor.run { self.currentHealthCheckInterval() }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { break }

                let port = await MainActor.run { self.profile.localSocksPort }
                let outcome = await self.healthCheckService.performHealthCheckDetailed(localPort: port)

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.sshService.isRunning, !self.manuallyDisconnected else { return }

                    if !outcome.socksListening {
                        self.handleHealthCheckFailure()
                        return
                    }

                    self.applySuccessfulHealthCheckOutcome(outcome, context: "periodic")
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

        let outcome = await healthCheckService.performHealthCheckDetailed(localPort: localPort)
        guard !Task.isCancelled else { return }

        applySuccessfulHealthCheckOutcome(outcome, context: "startup")

        reconnectAttempt = 0
        startHealthMonitoring()
    }

    private func handleHealthCheckFailure() {
        handleHealthCheckFailure(reason: "SOCKS proxy stopped responding.")
    }

    private func handleHealthCheckFailure(reason: String) {
        externalIP = "-"
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        connectProbeTask?.cancel()
        connectProbeTask = nil
        wakeRefreshTask?.cancel()
        wakeRefreshTask = nil

        scheduleReconnect(reason: reason)

        Task.detached { [sshService] in
            sshService.stop()
        }
    }

    private func handleTermination(info: SshTerminationInfo) {
        healthMonitorTask?.cancel()
        healthMonitorTask = nil
        connectProbeTask?.cancel()
        connectProbeTask = nil
        wakeRefreshTask?.cancel()
        wakeRefreshTask = nil
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
            appendEvent(
                message: "Reconnect stopped: attempts exhausted. reason=\(reason)",
                source: .system
            )
            status = .error("\(reason) Reconnect attempts exhausted. Open Settings, fix configuration, then reconnect.")
            reconnectAttempt = 0
            return
        }

        reconnectAttempt += 1
        let delay = reconnectPolicy.delaySeconds(forAttempt: reconnectAttempt)
        appendEvent(
            message: "Reconnect scheduled: attempt \(reconnectAttempt)/\(reconnectPolicy.maxAttempts) in \(delay)s. reason=\(reason)",
            source: .system
        )
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
                guard let self else { return }
                self.appendEvent(
                    message: "Reconnect attempt \(self.reconnectAttempt) starting now.",
                    source: .system
                )
                self.connect()
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
        let endpointCount = profile.normalizedExternalIPCheckURLs.count
        return "name=\(label), destination=\(profile.destination), sshPort=\(profile.sshPort), socksPort=\(profile.localSocksPort), auth=\(auth), ipCheck=\(ipCheck), ipEndpoints=\(endpointCount)"
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
        if old.normalizedExternalIPCheckURLs != new.normalizedExternalIPCheckURLs { changed.append("ipCheckURLs") }
        return changed.isEmpty ? "none" : changed.joined(separator: ",")
    }

    private func didHealthCheckFailForWake(_ outcome: HealthCheckOutcome) -> Bool {
        guard outcome.socksListening else { return true }
        guard profile.externalIPCheckEnabled else { return false }
        if case .success = outcome.externalIPResult {
            return false
        }
        return true
    }

    private func applySuccessfulHealthCheckOutcome(_ outcome: HealthCheckOutcome, context: String) {
        guard outcome.socksListening else { return }

        guard profile.externalIPCheckEnabled else {
            externalIP = "-"
            status = .connected
            return
        }

        guard let result = outcome.externalIPResult else {
            externalIP = "-"
            status = .degraded("External IP check returned no result.")
            appendEvent(message: "Tunnel partial (\(context)): no external health-check result.", source: .system)
            return
        }

        switch result {
        case .success(let ip, let endpoint):
            externalIP = ip
            status = .connected
            let endpointLabel = endpoint.host ?? endpoint.absoluteString
            appendEvent(
                message: "Tunnel health (\(context)): external IP \(ip) via \(endpointLabel).",
                source: .system
            )
        case .allFailed:
            externalIP = "-"
            let reason = result.summary
            status = .degraded("External IP check failed (\(reason)).")
            appendEvent(
                message: "Tunnel partial (\(context)): external checks failed. \(reason)",
                source: .system
            )
        }
    }

    private func currentHealthCheckInterval() -> Duration {
        switch status {
        case .degraded:
            return healthCheckIntervalDegraded
        default:
            return healthCheckIntervalConnected
        }
    }
}
