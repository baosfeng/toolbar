// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "NetworkMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "NetworkMonitorCore"
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["NetworkMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
