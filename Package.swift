// swift-tools-version: 5.9
// AIStat - native macOS menu bar app to monitor AI service quotas.
import PackageDescription

let package = Package(
    name: "AIStat",
    platforms: [
        // MenuBarExtra and SMAppService both require macOS 13 Ventura.
        .macOS(.v13)
    ],
    targets: [
        // No third-party dependencies: SwiftUI, AppKit, Security and
        // ServiceManagement are all system frameworks, auto-linked on macOS.
        .executableTarget(
            name: "AIStat",
            path: "Sources/AIStat",
            // Reserved for future bundled assets (provider glyphs, etc.).
            // Info.plist is copied by the Makefile, not declared as a resource.
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
