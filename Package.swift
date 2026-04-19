// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacProxyUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacProxyUI", targets: ["MacProxyUI"]),
        .executable(name: "AskpassHelper", targets: ["AskpassHelper"])
    ],
    targets: [
        .executableTarget(
            name: "AskpassHelper",
            path: "Tools",
            sources: ["AskpassHelper.swift"]
        ),
        .executableTarget(
            name: "MacProxyUI",
            dependencies: [],
            path: ".",
            exclude: [
                "Tools",
                "Packaging",
                "scripts",
                "QA_DOD_REPORT.md",
                "README.md"
            ],
            sources: [
                "MacProxyUIApp.swift",
                "AppDelegate.swift",
                "State/AppState.swift",
                "Models/ConnectionProfile.swift",
                "Models/ProxyStatus.swift",
                "Services/SshProcessService.swift",
                "Services/KeychainService.swift",
                "Services/HealthCheckService.swift",
                "Services/ReconnectCoordinator.swift",
                "Services/PortProbeService.swift",
                "Views/MainView.swift",
                "Views/SettingsView.swift",
                "Tray/StatusBarController.swift"
            ]
        )
    ]
)
