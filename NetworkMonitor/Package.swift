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
        // 展示纯逻辑（Hero 派生、单位排版、键位解析、组合键展示等）。另链接 Carbon：
        // 组合键展示要读 kVK_* / cmdKey 这些键码常量；Core 不依赖 Carbon，这段只能落在 UI。
        .target(
            name: "NetworkMonitorUI",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
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
        // 系统监控服务层（CPU / GPU / 内存 / 磁盘 / 温度 / Wi-Fi 链路采样）：只依赖 Core，不碰 AppKit。
        // 单独成 target 是为了让采样口径与「慢节拍闸门」能被 TestRunner 直接断言
        // （App 是可执行 target，测试够不着那里的类型）。
        .target(
            name: "NetworkMonitorFeatureSystemMetrics",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                // 免 root 采样：IOAccelerator / IOBlockStorageDriver 统计 / IOReport 功耗 / IOHID 温度
                .linkedFramework("IOKit"),
                // Wi-Fi 链路（RSSI / 信道 / 速率）
                .linkedFramework("CoreWLAN")
            ]
        ),
        // 剪贴板服务层（采集 / 粘贴 / 粘贴栈 / 图片落盘与回收 / 缩略图解码 / OCR 调度）：只依赖 Core。
        // 允许 import AppKit —— 采集与写回绕不开 NSPasteboard / NSRunningApplication，
        // 与 NetworkMonitorFeatureFeedback 同类；合成 ⌘V 与辅助功能判定另链接 ApplicationServices。
        // 单独成 target 是为了让「采集准入 / 粘贴降级 / 图片回收 / 缩略图重试」能被 TestRunner 直接断言。
        .target(
            name: "NetworkMonitorFeatureClipboard",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        // 输入体验层（鼠标滚轮平滑）：允许 import AppKit / CoreGraphics（事件 tap 与显示帧驱动），
        // 只依赖 Core。单独成 target 是为了让「识别判据 / tap 健康度 / 曲线与拆分」能被 TestRunner
        // 直接断言（App 是可执行 target，测不了），也把「会碰全局输入路径」的代码收在一个 target 里。
        .target(
            name: "NetworkMonitorFeatureSmoothScroll",
            dependencies: ["NetworkMonitorCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore")
            ]
        ),
        // 截图服务层（抓屏 / 写盘 / 写剪贴板 / OCR / 截图热键 / 偏好键）：依赖 Core + UI。
        // 允许 import AppKit（NSScreen / NSPasteboard / NSEvent）与 CoreGraphics / Vision /
        // ScreenCaptureKit / Carbon —— 这些是「系统 API → Core 值类型」翻译绕不开的。
        // 单独成 target 是为了让「写盘格式与尺寸、剪贴板选档、热键偏好归一化、按键翻译」
        // 能被 TestRunner 直接断言（App 是可执行 target，测不了）；
        // 覆盖层 / 工具条 / 贴图窗这些 UI 一律留在 App。
        .target(
            name: "NetworkMonitorFeatureSnip",
            dependencies: ["NetworkMonitorCore", "NetworkMonitorUI"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .executableTarget(
            name: "NetworkMonitor",
            dependencies: [
                "NetworkMonitorCore",
                "NetworkMonitorUI",
                "NetworkMonitorDesign",
                "NetworkMonitorFeatureBilling",
                "NetworkMonitorFeatureSnip",
                "NetworkMonitorFeatureFeedback",
                "NetworkMonitorFeatureDiagnostics",
                "NetworkMonitorFeatureSystemMetrics",
                "NetworkMonitorFeatureClipboard",
                "NetworkMonitorFeatureSmoothScroll"
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
                "NetworkMonitorFeatureDiagnostics",
                "NetworkMonitorFeatureSystemMetrics",
                "NetworkMonitorFeatureClipboard",
                "NetworkMonitorFeatureSmoothScroll",
                "NetworkMonitorFeatureSnip"
            ]
        ),
        // UI 自动化 CLI（nmcli）：纯系统框架直连目标进程做程序化验收，
        // 不依赖 cua、零第三方依赖，用法见 docs/开发指南/UI-自动化-CLI.md
        .executableTarget(
            name: "nmcli",
            // 页面通道的目标解析与常量与 app 共用一份（NetworkMonitorUI 是不依赖 AppKit 的纯逻辑库），
            // 否则 nmcli 里再抄一套字符串，改名时两边静默分叉
            dependencies: ["NetworkMonitorUI"],
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
