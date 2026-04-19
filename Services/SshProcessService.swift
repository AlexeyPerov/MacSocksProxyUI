import Foundation

struct SshTerminationInfo: Equatable {
    enum Kind: Equatable {
        case exited(Int32)
        case uncaughtSignal(Int32)
        case failedToLaunch
    }

    let kind: Kind
    let pid: Int32?
    let stderrTail: [String]
    let parsedFailure: SshParsedFailure?

    var exitCodeOrSignal: Int32? {
        switch kind {
        case .exited(let code):
            return code
        case .uncaughtSignal(let signal):
            return signal
        case .failedToLaunch:
            return nil
        }
    }
}

enum SshParsedFailure: Equatable {
    case permissionDenied
    case authenticationFailed
    case hostKeyVerificationFailed
    case connectionRefused
    case networkUnreachable
    case nameResolutionFailed
    case portBindFailed
    case generic(String)
}

enum SshAskpassConfiguration {
    /// SwiftPM: `AskpassHelper` next to `MacProxyUI` in the build products directory. App bundle: auxiliary executable.
    static func resolveHelperExecutableURL() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "AskpassHelper") {
            return url
        }
        let mainBinary = URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = mainBinary.deletingLastPathComponent().appendingPathComponent("AskpassHelper")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return nil
    }

    /// Environment so OpenSSH uses `SSH_ASKPASS` without a TTY (password supplied by our helper from Keychain).
    static func sshEnvironment(helperExecutable: URL, keychainAccount: String) -> [String: String] {
        [
            "SSH_ASKPASS": helperExecutable.path,
            "SSH_ASKPASS_REQUIRE": "force",
            "DISPLAY": ":0",
            "MACPROXYUI_KEYCHAIN_ACCOUNT": keychainAccount
        ]
    }
}

final class SshProcessService {
    private(set) var process: Process?

    /// Called when the SSH process exits for any reason **except** a user-initiated `stop()`.
    var onTermination: ((SshTerminationInfo) -> Void)?

    /// Incremental stderr lines (useful for future log UI). Does not include sensitive prompts beyond what ssh prints.
    var onStderrLine: ((String) -> Void)?

    private var stderrPipe: Pipe?
    private var stderrReadBuffer = Data()
    private var stderrLines: [String] = []
    private let maxStderrLines = 200

    private var suppressTerminationCallbacks = false

    var pid: Int32? {
        process?.processIdentifier
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(profile: ConnectionProfile, environment: [String: String] = [:]) throws {
        guard !isRunning else { return }

        let sshProcess = Process()
        sshProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        var args = [
            "-D", "\(profile.localSocksPort)",
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=3",
            "-p", "\(profile.sshPort)"
        ]
        if profile.useKeyAuthentication {
            args.append(contentsOf: ["-o", "BatchMode=yes"])
        } else {
            args.append(contentsOf: ["-o", "BatchMode=no", "-o", "NumberOfPasswordPrompts=1"])
        }
        args.append(profile.destination)
        sshProcess.arguments = args
        sshProcess.environment = ProcessInfo.processInfo.environment.merging(environment, uniquingKeysWith: { _, new in new })

        let pipe = Pipe()
        sshProcess.standardOutput = FileHandle.nullDevice
        sshProcess.standardInput = FileHandle.nullDevice
        sshProcess.standardError = pipe

        stderrPipe = pipe
        stderrReadBuffer = Data()
        stderrLines = []
        suppressTerminationCallbacks = false

        beginReadingStderr(from: pipe.fileHandleForReading)

        sshProcess.terminationHandler = { [weak self] terminated in
            self?.handleProcessTerminated(terminated)
        }

        do {
            try sshProcess.run()
        } catch {
            tearDownPipes()
            throw error
        }

        process = sshProcess
    }

    /// Stops the SSH process: `SIGTERM` first, then `SIGKILL` if it doesn't exit within `killTimeout`.
    ///
    /// Important: this may block briefly while waiting for the process to exit. Prefer calling it from a background queue.
    func stop(killTimeout: TimeInterval = 2.0) {
        guard let running = process else { return }

        suppressTerminationCallbacks = true
        stopReadingStderr()

        if running.isRunning {
            running.terminate()

            let deadline = Date().addingTimeInterval(killTimeout)
            while Date() < deadline, running.isRunning {
                usleep(50_000) // 50ms
            }

            if running.isRunning {
                kill(running.processIdentifier, SIGKILL)

                let hardDeadline = Date().addingTimeInterval(1.0)
                while Date() < hardDeadline, running.isRunning {
                    usleep(50_000) // 50ms
                }
            }
        }

        tearDownPipes()
        process = nil
        suppressTerminationCallbacks = false
    }

    private func handleProcessTerminated(_ terminated: Process) {
        stopReadingStderr()

        let pid: Int32? = terminated.processIdentifier

        let kind: SshTerminationInfo.Kind
        switch terminated.terminationReason {
        case .exit:
            kind = .exited(terminated.terminationStatus)
        case .uncaughtSignal:
            kind = .uncaughtSignal(terminated.terminationStatus)
        @unknown default:
            kind = .exited(terminated.terminationStatus)
        }

        let tail = Array(stderrLines.suffix(32))
        let parsed = Self.parseFailure(from: stderrLines)

        tearDownPipes()
        process = nil

        guard !suppressTerminationCallbacks else { return }

        onTermination?(
            SshTerminationInfo(
                kind: kind,
                pid: pid,
                stderrTail: tail,
                parsedFailure: parsed
            )
        )
    }

    private func beginReadingStderr(from handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fh in
            guard let self else {
                fh.readabilityHandler = nil
                return
            }

            let chunk = fh.availableData
            if chunk.isEmpty {
                fh.readabilityHandler = nil
                return
            }

            self.stderrReadBuffer.append(chunk)

            while true {
                guard let range = self.stderrReadBuffer.range(of: Data([0x0A])) else { break } // '\n'
                let lineData = self.stderrReadBuffer.subdata(in: self.stderrReadBuffer.startIndex..<range.lowerBound)
                self.stderrReadBuffer.removeSubrange(self.stderrReadBuffer.startIndex...range.lowerBound)

                let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines)
                    ?? ""

                guard !line.isEmpty else { continue }

                if self.stderrLines.count >= self.maxStderrLines {
                    self.stderrLines.removeFirst(self.stderrLines.count - self.maxStderrLines + 1)
                }
                self.stderrLines.append(line)
                self.onStderrLine?(line)
            }
        }
    }

    private func stopReadingStderr() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }

    private func tearDownPipes() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stderrPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForWriting.close()
        stderrPipe = nil
        stderrReadBuffer = Data()
    }

    static func parseFailure(from stderrLines: [String]) -> SshParsedFailure? {
        // Scan from the bottom: the last actionable error is usually most relevant.
        for line in stderrLines.reversed() {
            let s = line

            if s.contains("Permission denied") { return .permissionDenied }
            if s.contains("Authentication failed") { return .authenticationFailed }
            if s.contains("Host key verification failed") { return .hostKeyVerificationFailed }
            if s.contains("Connection refused") { return .connectionRefused }
            if s.contains("No route to host") || s.contains("Network is unreachable") { return .networkUnreachable }
            if s.contains("Could not resolve hostname") || s.contains("nodename nor servname provided") { return .nameResolutionFailed }
            if s.contains("Address already in use") { return .portBindFailed }
            if s.contains("kex_exchange_identification") { return .generic("SSH handshake failed (kex_exchange_identification).") }
        }

        return nil
    }

    static func humanReadableMessage(for info: SshTerminationInfo) -> String {
        if let parsed = info.parsedFailure {
            switch parsed {
            case .permissionDenied:
                return "SSH permission denied (check username/key permissions)."
            case .authenticationFailed:
                return "SSH authentication failed (password/key)."
            case .hostKeyVerificationFailed:
                return "Host key verification failed (verify known_hosts / server identity)."
            case .connectionRefused:
                return "Connection refused (wrong SSH port or sshd not running)."
            case .networkUnreachable:
                return "Network unreachable (routing/VPN/firewall)."
            case .nameResolutionFailed:
                return "Could not resolve hostname (DNS)."
            case .portBindFailed:
                return "Local SOCKS port bind failed (port already in use?)."
            case .generic(let message):
                return message
            }
        }

        switch info.kind {
        case .failedToLaunch:
            return "SSH failed to launch."
        case .exited(let code):
            return "SSH exited with code \(code)."
        case .uncaughtSignal(let signal):
            return "SSH terminated by signal \(signal)."
        }
    }
}
