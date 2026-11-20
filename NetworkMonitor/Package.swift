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
            name: "NetworkMonitorUI",
            dependencies: ["NetworkMonitorCore"]
        ),
        // 设计系统（渲染基础层）：卡片令牌 / 页头页脚骨架 / 主题转译 / 动效令牌 / 自绘组件库。
        // 单独成 target 是为了让「设计系统」不再寄生在 MenuPanel 页面目录里，
        // 页面只依赖它、它不反向依赖页面；允许 import AppKit（绘制本身就在这一层）。
        .target(
            name: "NetworkMonitorDesign",
            dependencies: ["NetworkMonitorCore", "NetworkMonitorUI"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore")
            ]
        ),
        // 额度服务层（provider 实现 + 状态管理器 + 提醒）：只依赖 Core，不碰 AppKit。
        // 单独成 target 是为了让业务逻辑能被 TestRunner 直接断言（App 是可执行 target，测不了）。
        .target(
            name: "NetworkMonitorFeatureBilling",
            dependencies: ["NetworkMonitorCore"]
        ),
        // 操作反馈层（音效 / 触觉 / 成对出口）：允许 import AppKit（NSSound / NSHapticFeedbackManager），
        // 只依赖 Core。单独成 target 是为了让「cue 转发 / 档位映射」能被 TestRunner 直接断言。
        .target(
            name: "NetworkMonitorFeatureFeedback",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        // 诊断层（主线程看门狗 + 心跳现场）：允许 import AppKit（NSEvent 本地事件监听），
        // 只依赖 Core（复用 Core 的 MainThreadWatchdogPolicy）。停顿判定口径可被 TestRunner 直接断言。
        .target(
            name: "NetworkMonitorFeatureDiagnostics",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: [
                "NetworkMonitorCore",
                "NetworkMonitorUI",
                "NetworkMonitorDesign",
                "NetworkMonitorFeatureBilling",
                "NetworkMonitorFeatureFeedback",
                "NetworkMonitorFeatureDiagnostics"
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
            dependencies: [
                "NetworkMonitorCore",
                "NetworkMonitorUI",
                "NetworkMonitorFeatureBilling",
                "NetworkMonitorFeatureFeedback",
                "NetworkMonitorFeatureDiagnostics"
            ]
        ),
        // UI 自动化 CLI（nmcli）：纯系统框架直连目标进程做程序化验收，
        // 不依赖 cua、零第三方依赖，用法见 docs/开发指南/UI-自动化-CLI.md
        .executableTarget(
            name: "nmcli",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
