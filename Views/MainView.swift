import SwiftUI
import MacProxyCore

struct MainView: View {
    static let minimumWindowWidth: CGFloat = 434
    static let minimumWindowHeight: CGFloat = 760
    static let maximumWindowWidth: CGFloat = 542
    static let maximumWindowHeight: CGFloat = 900

    @ObservedObject var appState: AppState
    @State private var isPrimaryButtonHovered = false

    private var primaryButtonTitle: String {
        switch appState.status {
        case .disconnected, .error:
            return "Connect"
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return "Reconnecting"
        case .connected:
            return "Connected"
        case .degraded:
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

    private var isBusyState: Bool {
        switch appState.status {
        case .connecting, .reconnecting:
            return true
        default:
            return false
        }
    }

    private var primaryCircleColor: Color {
        switch appState.status {
        case .connected:
            return WindowTheme.connectedCircle
        case .connecting, .reconnecting:
            return WindowTheme.busyCircle
        default:
            return WindowTheme.primaryText
        }
    }

    private var primaryButtonScale: CGFloat {
        guard primaryButtonIsEnabled else { return 1.0 }
        return isPrimaryButtonHovered ? 1.03 : 1.0
    }

    private enum LogLevel {
        case lowPriority
        case error
        case warning
        case neutral
    }

    private func logLevel(for event: MainScreenEvent) -> LogLevel {
        let raw = event.message.lowercased()
        if raw.contains("channel") && raw.contains("open failed") && raw.contains("connection timed out") {
            return .lowPriority
        }
        if raw.contains("error")
            || raw.contains("failed")
            || raw.contains("exited")
            || raw.contains("refused")
            || raw.contains("denied")
            || raw.contains("unreachable") {
            return .error
        }
        if raw.contains("warning")
            || raw.contains("degraded")
            || raw.contains("retry")
            || raw.contains("reconnecting")
            || raw.contains("partial") {
            return .warning
        }
        return .neutral
    }

    private func color(for logLevel: LogLevel) -> Color {
        switch logLevel {
        case .lowPriority:
            return WindowTheme.subduedLog
        case .error:
            return WindowTheme.errorLog
        case .warning:
            return WindowTheme.warningLog
        case .neutral:
            return WindowTheme.primaryText
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Text("Status: \(appState.status.title.lowercased())")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(WindowTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Proxy status")
                    .accessibilityValue(appState.status.title)

                Button {
                    appState.isSettingsPresented = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WindowTheme.primaryText)
                        .frame(width: 42, height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(WindowTheme.panelBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(WindowTheme.primaryText, lineWidth: 1.75)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: [.command])
                .accessibilityLabel("Open settings")
            }
            .padding(.top, 6)
            .padding(.bottom, -4)

            Text("External IP (via SOCKS): \(appState.externalIP)")
                .font(.system(size: 13.6, weight: .regular, design: .default))
                .foregroundStyle(WindowTheme.externalIPText)
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)

            if appState.needsInitialSetup {
                Text("Open Settings to add host, username, and port values.")
                    .font(.footnote)
                    .foregroundStyle(WindowTheme.secondaryText)
            }

            Spacer(minLength: 0)

            Button(action: handlePrimaryButtonTap) {
                ZStack {
                    Circle()
                        .fill(primaryCircleColor.opacity(0.13))
                    Circle()
                        .stroke(primaryCircleColor, lineWidth: isBusyState ? 4 : 3)
                    if isBusyState {
                        TimelineView(.animation) { context in
                            let rotation = context.date.timeIntervalSinceReferenceDate * 280
                            Circle()
                                .trim(from: 0.06, to: 0.28)
                                .stroke(primaryCircleColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(rotation))
                                .padding(12)
                        }
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 25, weight: .medium, design: .default))
                        .foregroundStyle(primaryCircleColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 210, height: 210)
                .scaleEffect(primaryButtonScale)
                .shadow(color: primaryCircleColor.opacity(isPrimaryButtonHovered ? 0.28 : 0.12), radius: isPrimaryButtonHovered ? 16 : 8)
            }
            .buttonStyle(.plain)
            .disabled(!primaryButtonIsEnabled)
            .onHover { hovering in
                isPrimaryButtonHovered = hovering
            }
            .animation(.easeOut(duration: 0.18), value: isPrimaryButtonHovered)
            .accessibilityLabel("\(primaryButtonTitle) proxy")

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 28)
                .fill(WindowTheme.panelBackground)
                .frame(maxWidth: .infinity, minHeight: 290, maxHeight: 290)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(WindowTheme.primaryText, lineWidth: 2.5)
                )
                .overlay(alignment: .topLeading) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(appState.mainScreenEvents) { event in
                                Text("[\(event.timestampLabel)] \(event.message)")
                                    .foregroundStyle(color(for: logLevel(for: event)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if appState.mainScreenEvents.isEmpty {
                                Text("No events yet")
                                    .foregroundStyle(WindowTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(.system(size: 13.5, weight: .regular, design: .default))
                        .padding(18)
                    }
                    .textSelection(.enabled)
                }
        }
        .padding(20)
        .background(WindowTheme.windowBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .frame(
            minWidth: Self.minimumWindowWidth,
            maxWidth: Self.maximumWindowWidth,
            minHeight: Self.minimumWindowHeight,
            maxHeight: Self.maximumWindowHeight
        )
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
                .frame(minWidth: 560, maxWidth: 560, minHeight: 620, maxHeight: 620)
        }
    }
}
