import Foundation
import NetworkMonitorCore
import NetworkMonitorFeatureSmoothScroll

// MARK: - 鼠标滚轮平滑（feature target 跨 target 边界）

/// 跨 target 断言：识别判据 / tap 健康度 / kill switch / 引擎状态迁移
/// 都住在 `NetworkMonitorFeatureSmoothScroll`，TestRunner 直接 import 该模块。
///
/// 改造前测不到：这类逻辑在可执行 target `NetworkMonitor` 里，测试只能看 Core；
/// 「触控板事件真的被排除」「tap 连续 3 次被禁用后真的会停用」「环境变量真能硬关闭」
/// 这一层没有任何机器判据。这里把三条安全边界都变成断言。
///
/// 注意：本套件**不装真 tap**（那会接管真实输入、且依赖辅助功能权限），
/// 只驱动纯类型与「不装 tap 就能判定的引擎入口」。
@MainActor
func runSmoothScrollFeatureBoundaryTests() {
    print("\n🧪 Testing 鼠标滚轮平滑跨 target 边界（识别 / 健康度 / kill switch / 状态）...")
    testInjectedEventRecognition()
    testTrackpadAndMomentumExcluded()
    testTapHealthGivesUpAfterThreeDisables()
    testKillSwitch()
    testEngineStateGuardsWithoutTap()
    testEngineStateTexts()
    testFeatureSourceBoundary()
    print("✅ 鼠标滚轮平滑跨 target 边界 works")
}

// MARK: - 回投标记识别

@MainActor private func testInjectedEventRecognition() {
    // 这行能编译即证明：魔数标记与识别函数已跨 target 公开
    let marker = ScrollEventClassifier.injectionMarker
    assertEqual(marker, 0x5343_524F_4C4C, "魔数标记冻结（改动会让升级后的首个事件被误判）")
    assertEqual(ScrollEventClassifier.isOwnInjectedEvent(sourceUserData: marker), true,
                "带魔数标记的事件识别为自己回投的")
    assertEqual(ScrollEventClassifier.isOwnInjectedEvent(sourceUserData: 0), false,
                "真实 HID 事件（userData 0）不识别")
    assertEqual(ScrollEventClassifier.isOwnInjectedEvent(sourceUserData: marker &+ 1), false,
                "标记相邻值不识别（不做范围匹配）")
}

// MARK: - 触控板 / 惯性排除

@MainActor private func testTrackpadAndMomentumExcluded() {
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 0, momentumPhase: 0,
                                                            isContinuous: false),
                true, "纯鼠标滚轮（无 phase / 无惯性 / 非连续）才可平滑")
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 1, momentumPhase: 0,
                                                            isContinuous: false),
                false, "触控板（began phase）不平滑")
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 4, momentumPhase: 0,
                                                            isContinuous: false),
                false, "妙控鼠标 / 驱动级平滑（changed phase）不平滑")
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 0, momentumPhase: 2,
                                                            isContinuous: false),
                false, "惯性滑行（momentumPhase）不平滑")
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 1, momentumPhase: 3,
                                                            isContinuous: true),
                false, "phase + 惯性 + 连续滚动三重命中：放行")
    assertEqual(ScrollEventClassifier.isSmoothableMouseWheel(phase: 0, momentumPhase: 0,
                                                            isContinuous: true),
                false, "连续滚动即使没有 phase 也不接管（驱动已经平滑过）")
}

// MARK: - tap 健康度

@MainActor private func testTapHealthGivesUpAfterThreeDisables() {
    assertEqual(ScrollTapHealth.maximumConsecutiveDisables, 3, "连续禁用上限 3 次")
    var health = ScrollTapHealth()
    assertEqual(health.consecutiveDisables, 0, "初始计数为 0")
    assertEqual(health.recordDisable(), .reenable, "第 1 次禁用：重新启用")
    assertEqual(health.recordDisable(), .reenable, "第 2 次禁用：再重新启用")
    assertEqual(health.recordDisable(), .giveUp, "第 3 次禁用：判定不稳定，停用整个功能")
    assertEqual(health.consecutiveDisables, 3, "计数累计到 3")

    var recovered = ScrollTapHealth()
    _ = recovered.recordDisable()
    _ = recovered.recordDisable()
    recovered.recordHealthyEvent()
    assertEqual(recovered.consecutiveDisables, 0, "处理过真实滚轮事件即视为恢复健康，计数清零")
    assertEqual(recovered.recordDisable(), .reenable, "清零后再禁用从 1 重新计")

    var interleaved = ScrollTapHealth()
    for _ in 0..<2 {
        _ = interleaved.recordDisable()
        interleaved.recordHealthyEvent()
    }
    assertEqual(interleaved.recordDisable(), .reenable,
                "交替健康与禁用永远不判死（不是累计 3 次就停）")
}

// MARK: - kill switch

@MainActor private func testKillSwitch() {
    let key = ScrollSmoothingKillSwitch.environmentKey
    assertEqual(key, "NM_SCROLL_SMOOTHING_DISABLE", "kill switch 环境变量名冻结")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [:]), false, "未设置时不禁用")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [key: "1"]), true, "=1 关闭")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [key: "true"]), true, "=true 关闭")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [key: " YES "]), true,
                "=YES（带空格、大写）关闭")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [key: "0"]), false, "=0 不关闭")
    assertEqual(ScrollSmoothingKillSwitch.isDisabled(environment: [key: ""]), false, "空串不关闭")
}

// MARK: - 引擎状态（不装 tap）

@MainActor private func testEngineStateGuardsWithoutTap() {
    let logger = RecordingLogger()
    let storage = InMemoryStorage()
    let settings = SmoothScrollSettings(storage: storage)

    // 默认关闭：reload 不装 tap、状态停留 idle
    let engine = ScrollSmoothingEngine(settings: settings, logger: logger, environment: [:])
    assertEqual(engine.state, .idle, "初始状态 idle")
    engine.reload()
    assertEqual(engine.state, .idle, "偏好关闭时 reload 不接管全局输入")
    assertEqual(engine.isRunning, false, "未运行时 isRunning 为 false")

    // kill switch：偏好打开也不装 tap
    settings.setEnabled(true)
    let killed = ScrollSmoothingEngine(settings: settings, logger: logger,
                                       environment: [ScrollSmoothingKillSwitch.environmentKey: "1"])
    killed.reload()
    assertEqual(killed.state, .disabledByEnvironment, "环境变量硬关闭：不装 tap")
    assertEqual(killed.isRunning, false, "被环境变量关闭时未运行")
    assertEqual(logger.all.contains { $0.contains("NM_SCROLL_SMOOTHING_DISABLE") }, true,
                "被环境变量关闭时留一条说明日志（现场排障可见）")

    // 关掉偏好再把已停用的引擎 reload 一次：状态回到 idle
    killed.stop()
    assertEqual(killed.state, .idle, "stop 后回到 idle")
    engine.stop()
}

// MARK: - 状态文案

@MainActor private func testEngineStateTexts() {
    let states: [ScrollSmoothingEngineState] = [.idle, .running, .disabledByEnvironment,
                                                .tapUnavailable, .stoppedAfterRepeatedDisables]
    assertEqual(states.count, 5, "五种引擎状态")
    assertEqual(states.allSatisfy { !$0.displayText.isEmpty }, true, "每种状态都有说明文案")
    assertEqual(Set(states.map(\.displayText)).count, 5, "五条文案互不相同（设置页能区分）")
    assertContains(ScrollSmoothingEngineState.tapUnavailable.displayText, "辅助功能",
                   "无 tap 的文案点名「辅助功能」权限")
    assertContains(ScrollSmoothingEngineState.stoppedAfterRepeatedDisables.displayText, "自动停用",
                   "连续禁用的文案说明会自动停用")
}

// MARK: - 源码边界

@MainActor private func testFeatureSourceBoundary() {
    let runnerDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourcesDirectory = runnerDirectory.deletingLastPathComponent()
    let featureDirectory = sourcesDirectory.appendingPathComponent("NetworkMonitorFeatureSmoothScroll")
    let coreDirectory = sourcesDirectory
        .appendingPathComponent("NetworkMonitorCore/Infrastructure/SmoothScroll")

    let featureFiles = swiftFiles(in: featureDirectory)
    assertEqual(featureFiles.count >= 3, true, "平滑功能 target 至少三个源文件（实际 \(featureFiles.count)）")

    var importsAppTarget = 0
    var readsAppContext = 0
    var prints = 0
    for file in featureFiles {
        // 只看代码行：注释里说明「功能层不取 AppContext.shared」不该被判红
        for line in codeLines(of: file) {
            if line == "import NetworkMonitor" { importsAppTarget += 1 }
            if line.contains("AppContext.shared") { readsAppContext += 1 }
            if line.contains("print(") { prints += 1 }
        }
    }
    assertEqual(importsAppTarget, 0, "功能 target 不 import App（不能反向依赖可执行 target）")
    assertEqual(readsAppContext, 0, "功能 target 不读 AppContext.shared（logger 由调用方注入）")
    assertEqual(prints, 0, "功能 target 不 print（日志统一走 LoggingService）")

    let coreFiles = swiftFiles(in: coreDirectory)
    assertEqual(coreFiles.count >= 3, true, "Core 侧平滑源文件至少三个（实际 \(coreFiles.count)）")
    var importsAppKit = 0
    for file in coreFiles {
        if codeLines(of: file).contains("import AppKit") { importsAppKit += 1 }
    }
    assertEqual(importsAppKit, 0, "Core 侧平滑逻辑不 import AppKit（纯逻辑可测）")
}

/// 文件里的代码行（去掉行注释与空行：注释里提到禁词不算违规）
private func codeLines(of file: URL) -> [String] {
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }
}

/// 目录下的 .swift 文件（不递归：本 target 是平铺的）
private func swiftFiles(in directory: URL) -> [URL] {
    let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
    return contents.filter { $0.pathExtension == "swift" }
}
