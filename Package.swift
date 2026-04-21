// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacProxyUI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "MacProxyCore", targets: ["MacProxyCore"]),
        .executable(name: "MacProxyUI", targets: ["MacProxyUI"]),
        .executable(name: "AskpassHelper", targets: ["AskpassHelper"])
    ],
    targets: [
        .executableTarget(
            name: "AskpassHelper",
            path: "Tools",
            sources: ["AskpassHelper.swift"]
        ),
        .target(
            name: "MacProxyCore",
            dependencies: [],
            path: ".",
            exclude: [
                "Tools",
                "Packaging",
                "Images",
                "scripts",
                "Tests",
                "LICENSE",
                "Tray",
                "Views",
                "MacProxyUIApp.swift",
                "AppDelegate.swift",
                "README.md"
            ],
            sources: [
                "State/AppState.swift",
                "State/ProfileStore.swift",
                "Models/ConnectionProfile.swift",
                "Models/ProxyStatus.swift",
                "Services/SshProcessService.swift",
                "Services/KeychainService.swift",
                "Services/HealthCheckService.swift",
                "Services/ReconnectCoordinator.swift",
                "Services/ReconnectPolicy.swift",
                "Services/PortProbeService.swift",
                "Services/DiagnosticsStore.swift"
            ]
        ),
        .executableTarget(
            name: "MacProxyUI",
            dependencies: ["MacProxyCore"],
            path: ".",
            exclude: [
                "Tools",
                "Packaging",
                "State",
                "Models",
                "Services",
                "scripts",
                "Tests",
                "LICENSE",
                "README.md"
            ],
            sources: [
                "MacProxyUIApp.swift",
                "AppDelegate.swift",
                "Views/MainView.swift",
                "Views/SettingsView.swift",
                "Tray/StatusBarController.swift"
            ],
            resources: [
                .copy("Images")
            ]
        ),
        .testTarget(
            name: "MacProxyCoreTests",
            dependencies: ["MacProxyCore"],
            path: "Tests/MacProxyCoreTests"
        )
    ]
)
