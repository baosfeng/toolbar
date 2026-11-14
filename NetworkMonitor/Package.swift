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
        // 与 AppKit / Core 都无关的展示纯逻辑（Hero 派生、单位排版等），
        // 让 TestRunner 能直接断言 UI 口径而不必 import 可执行 target。
        .target(
            name: "NetworkMonitorUI"
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: [
                "NetworkMonitorCore",
                "NetworkMonitorUI"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("ServiceManagement"),
                // 自定义音效导入：AVAudioFile 解码 mp3 / m4a 并转成系统通知能用的 AIFF
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreWLAN"),
                // 全局快捷键（剪贴板历史）依赖 Carbon 的 RegisterEventHotKey
                .linkedFramework("Carbon"),
                // 系统监控采样：IOKit 取 GPU 加速器 / 块存储统计与温度服务
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "TestRunner",
            dependencies: ["NetworkMonitorCore", "NetworkMonitorUI"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
