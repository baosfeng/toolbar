// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "NetworkMonitor",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/ChartsOrg/Charts.git", .upToNextMajor(from: "5.1.0"))
    ],
    targets: [
        .target(
            name: "NetworkMonitorCore"
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: [
                "NetworkMonitorCore",
                .product(name: "DGCharts", package: "Charts")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreWLAN"),
                // 全局快捷键（剪贴板历史）依赖 Carbon 的 RegisterEventHotKey
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["NetworkMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
