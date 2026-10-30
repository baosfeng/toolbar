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
            dependencies: [
                "NetworkMonitorCore"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreWLAN"),
                // 全局快捷键（剪贴板历史）依赖 Carbon 的 RegisterEventHotKey
                .linkedFramework("Carbon"),
                // 系统监控采样：IOKit 取 GPU 加速器 / 块存储统计与温度服务
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["NetworkMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
