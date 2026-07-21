// swift-tools-version: 5.9
// AIMonitor - native macOS menu bar app to monitor AI service quotas.
import PackageDescription

let package = Package(
    name: "AIMonitor",
    platforms: [
        // MenuBarExtra and SMAppService both require macOS 13 Ventura.
        .macOS(.v13)
    ],
    targets: [
        // No third-party dependencies: SwiftUI, AppKit, Security and
        // ServiceManagement are all system frameworks, auto-linked on macOS.
        .executableTarget(
            name: "AIMonitor",
            path: "Sources/AIMonitor",
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
