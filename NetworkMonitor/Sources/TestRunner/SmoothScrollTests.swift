import Foundation
import NetworkMonitorCore

// MARK: - 鼠标滚轮平滑（Core 纯逻辑）

/// Core 侧口径 —— 曲线 / 拆分 / 参数归一化 / 帧序列 / 偏好读写
///
/// 这一层全是纯函数，断言的重点不是「跑通」，而是三条**不该漂移的性质**：
/// 1. 曲线端点固定（value(0)=0、value(1)=1）、单调不减、关于 0.5 对称 ——
///    端点漂了就会「滚一下少一截 / 多一截」；
/// 2. 拆分与帧序列**位移守恒**（Σ == 总位移）—— 不守恒就是累积漂移；
/// 3. 偏好缺键 / 越界 / NaN 一律回落收敛 —— 引擎拿到的一定是安全区间内的值。
func runSmoothScrollTests() {
    print("\n🧪 Testing 鼠标滚轮平滑曲线与拆分（端点 / 守恒 / 归一化）...")
    testCurveEndpoints()
    testCurveShape()
    testCurveWeights()
    testSplitter()
    testParametersClamping()
    testMotionFrameDeltas()
    testSettingsDefaultsAndRoundTrip()
    print("✅ 鼠标滚轮平滑曲线与拆分 works")
}

// MARK: - 曲线

private func testCurveEndpoints() {
    assertEqual(SmoothScrollCurve.value(at: 0), 0, "进度 0 位移 0")
    assertEqual(SmoothScrollCurve.value(at: 1), 1, "进度 1 位移满")
    assertEqual(SmoothScrollCurve.value(at: 0.5), 0.5, "进度 0.5 位移一半（对称中点）")
    assertEqual(SmoothScrollCurve.value(at: -0.5), 0, "负进度收敛到 0")
    assertEqual(SmoothScrollCurve.value(at: 2), 1, "大于 1 的进度收敛到 1")
    assertEqual(SmoothScrollCurve.value(at: .nan), 0, "NaN 进度按 0 处理（不崩、不产生 NaN 位移）")
    assertEqual(SmoothScrollCurve.value(at: .infinity), 1, "无穷进度收敛到 1")
}

private func testCurveShape() {
    // 单调不减：抽样全区间，任何一段回退都意味着「滚动方向反转」
    var previous = -1.0
    var monotonic = true
    for index in 0...100 {
        let value = SmoothScrollCurve.value(at: Double(index) / 100)
        if value < previous { monotonic = false }
        previous = value
    }
    assertEqual(monotonic, true, "整条曲线单调不减")

    // 关于 0.5 对称：value(p) + value(1-p) == 1
    assertClose(SmoothScrollCurve.value(at: 0.2) + SmoothScrollCurve.value(at: 0.8), 1,
                "曲线关于 0.5 对称（0.2 与 0.8 互补）")
    assertClose(SmoothScrollCurve.value(at: 0.1) + SmoothScrollCurve.value(at: 0.9), 1,
                "曲线关于 0.5 对称（0.1 与 0.9 互补）")

    // 两端一阶导为 0：开头与结尾都比线性慢（起止不顿挫）
    assertEqual(SmoothScrollCurve.value(at: 0.05) < 0.01, true,
                "起点附近远慢于线性（5% 进度只走不到 1% 位移）")
    assertEqual(SmoothScrollCurve.value(at: 0.05) < 0.05, true, "起点位移小于线性进度")
    assertEqual(SmoothScrollCurve.value(at: 0.95) > 0.95, true, "终点位移大于线性进度（缓出）")
}

private func testCurveWeights() {
    assertEqual(SmoothScrollCurve.weights(count: 0).isEmpty, true, "0 帧没有权重")
    assertEqual(SmoothScrollCurve.weights(count: 1), [1], "1 帧走完全程")

    let weights = SmoothScrollCurve.weights(count: 8)
    assertEqual(weights.count, 8, "帧数即权重个数")
    assertClose(weights.reduce(0, +), 1, tolerance: 1e-12, "权重和为 1（位移守恒的前提）")
    assertEqual(weights.allSatisfy { $0 >= 0 }, true, "权重非负")
    // 两端一阶导为 0：首末帧都比均分小，中段比均分大（缓入 + 缓出）
    assertEqual(weights[0] < 1.0 / 8.0, true, "首帧权重小于均分（缓入）")
    assertEqual(weights.last! < 1.0 / 8.0, true, "末帧权重小于均分（缓出）")
    assertEqual(weights[3] > 1.0 / 8.0, true, "中段权重大于均分（曲线中段最快）")
}

// MARK: - 拆分

private func testSplitter() {
    assertEqual(SmoothScrollSplitter.split(delta: 0, step: 1).isEmpty, true, "0 增量不拆分")
    assertEqual(SmoothScrollSplitter.split(delta: .nan, step: 1).isEmpty, true, "NaN 增量不拆分")
    assertEqual(SmoothScrollSplitter.split(delta: .infinity, step: 1).isEmpty, true, "无穷增量不拆分")

    let single = SmoothScrollSplitter.split(delta: 0.4, step: 1)
    assertEqual(single.count, 1, "小于一步的增量不拆")
    assertClose(single[0], 0.4, "单段即原值")

    let three = SmoothScrollSplitter.split(delta: 3, step: 1)
    assertEqual(three.count, 3, "3 行 / 步长 1 行 → 3 段")
    assertClose(three.reduce(0, +), 3, tolerance: 1e-12, "拆分后和恰好等于原增量")
    assertEqual(three.allSatisfy { abs($0) <= 1 + 1e-12 }, true, "每段不超过步长")

    let negative = SmoothScrollSplitter.split(delta: -2.5, step: 1)
    assertEqual(negative.count, 3, "-2.5 行 / 步长 1 行 → 3 段（向上取整）")
    assertClose(negative.reduce(0, +), -2.5, tolerance: 1e-12, "负增量同样守恒")
    assertEqual(negative.allSatisfy { $0 <= 0 }, true, "负增量不出现反向段")

    let huge = SmoothScrollSplitter.split(delta: 1_000_000_000, step: 0.01)
    assertEqual(huge.count, SmoothScrollSplitter.maximumSteps, "超大增量按上限封顶段数")
    assertClose(huge.reduce(0, +), 1_000_000_000, tolerance: 1, "封顶后仍然守恒")

    assertEqual(SmoothScrollSplitter.split(delta: 2.5, step: 0).count, 3, "步长非法（0）按 1 处理")
    assertEqual(SmoothScrollSplitter.split(delta: 2.5, step: .nan).count, 3, "步长 NaN 按 1 处理")
}

// MARK: - 参数归一化

private func testParametersClamping() {
    assertEqual(SmoothScrollParameters.defaults.enabled, false, "默认关闭")
    assertEqual(SmoothScrollParameters.defaults.speedGain, 1, "默认增益 1.00 倍")
    assertEqual(SmoothScrollParameters.defaults.duration, 0.18, "默认时长 180 ms")
    assertEqual(SmoothScrollParameters.defaults.minStep, 0.5, "默认最短步长 0.5 行")
    assertEqual(SmoothScrollParameters.defaults.reverseDirection, false, "默认不反向")

    assertEqual(SmoothScrollParameters(speedGain: 99).clamped.speedGain,
                SmoothScrollParameters.speedGainRange.upperBound, "增益超上界收敛")
    assertEqual(SmoothScrollParameters(speedGain: -1).clamped.speedGain,
                SmoothScrollParameters.speedGainRange.lowerBound, "增益超下界收敛")
    assertEqual(SmoothScrollParameters(speedGain: .nan).clamped.speedGain,
                SmoothScrollParameters.defaultSpeedGain, "增益 NaN 回落默认")
    assertEqual(SmoothScrollParameters(duration: .infinity).clamped.duration,
                SmoothScrollParameters.defaultDuration, "时长无穷回落默认")
    assertEqual(SmoothScrollParameters(minStep: 100).clamped.minStep,
                SmoothScrollParameters.minStepRange.upperBound, "步长超上界收敛")

    let reverse = SmoothScrollParameters(enabled: true, speedGain: 2, reverseDirection: true)
    assertEqual(reverse.directionSign, -1, "反向滚动方向系数为 -1")
    assertClose(reverse.scaledDelta(3), -6, "反向 + 2 倍增益：3 行 → -6 行")
    assertEqual(reverse.scaledDelta(.nan), 0, "NaN 增量换算为 0（不把 NaN 带进事件构造）")
    assertEqual(SmoothScrollParameters().scaledDelta(3), 3, "默认 1 倍且不反向：原样")
}

// MARK: - 帧序列

private func testMotionFrameDeltas() {
    let enabled = SmoothScrollParameters(enabled: true, speedGain: 1, duration: 0.18, minStep: 0.5)
    assertEqual(SmoothScrollMotion.frameDeltas(delta: 3, parameters: .defaults, framesPerSecond: 60),
                [], "关闭时不平滑（空帧序列）")
    assertEqual(SmoothScrollMotion.frameDeltas(delta: 0, parameters: enabled, framesPerSecond: 60),
                [], "0 增量不产生帧")

    // 密度上界：3 行 / 0.5 行 = 6 步 < 0.18 × 60 = 11 帧 → 取 6
    let frames = SmoothScrollMotion.frameDeltas(delta: 3, parameters: enabled, framesPerSecond: 60)
    assertEqual(frames.count, 6, "帧数受最短步长约束（3 行 / 0.5 行 = 6 帧）")
    assertClose(frames.reduce(0, +), 3, tolerance: 1e-12, "逐帧位移总和等于原始增量")

    // 跨度上界：60 行 / 0.1 行 = 600 步 > 0.18 × 120 = 21.6 → 22 帧
    let dense = SmoothScrollParameters(enabled: true, duration: 0.18, minStep: 0.1)
    let capped = SmoothScrollMotion.frameDeltas(delta: 60, parameters: dense, framesPerSecond: 120)
    assertEqual(capped.count, 22, "帧数受时长 × 刷新率约束（120Hz × 0.18s ≈ 22 帧）")
    assertClose(capped.reduce(0, +), 60, tolerance: 1e-12, "封顶后仍然守恒")

    assertEqual(SmoothScrollMotion.frameCount(delta: 0, parameters: enabled, framesPerSecond: 60), 1,
                "0 增量按 1 帧（调用方据此判断不需要动画）")
    assertEqual(SmoothScrollMotion.frameCount(delta: 3, parameters: enabled, framesPerSecond: 0), 6,
                "刷新率非法时按 60Hz 兜底")

    let fast = SmoothScrollParameters(enabled: true, speedGain: 2, minStep: 0.5)
    assertClose(SmoothScrollMotion.frameDeltas(delta: 3, parameters: fast, framesPerSecond: 60)
                    .reduce(0, +), 6, tolerance: 1e-12, "增益 2 倍：总位移翻倍")

    let reversed = SmoothScrollParameters(enabled: true, minStep: 0.5, reverseDirection: true)
    assertEqual(SmoothScrollMotion.frameDeltas(delta: 3, parameters: reversed, framesPerSecond: 60)
                    .allSatisfy { $0 < 0 }, true, "反向滚动时每帧都为负")
}

// MARK: - 偏好

private func testSettingsDefaultsAndRoundTrip() {
    assertEqual(SmoothScrollPreferenceKey.all.count, 5, "五项偏好键")
    assertEqual(Set(SmoothScrollPreferenceKey.all).count, 5, "偏好键互不重复")
    assertEqual(SmoothScrollPreferenceKey.enabled, "scroll.smoothing.enabled", "开关键名冻结")
    assertEqual(SmoothScrollPreferenceKey.reverse, "scroll.smoothing.reverse", "反向键名冻结")

    let storage = InMemoryStorage()
    let settings = SmoothScrollSettings(storage: storage)
    assertEqual(settings.isEnabled, false, "缺键即关")
    assertEqual(settings.parameters, SmoothScrollParameters.defaults, "缺键回落默认参数")

    settings.setEnabled(true)
    settings.setSpeedGain(1.8)
    settings.setDuration(0.3)
    settings.setMinStep(0.25)
    settings.setReverseDirection(true)
    let saved = settings.parameters
    assertEqual(saved.enabled, true, "开关可读写")
    assertClose(saved.speedGain, 1.8, "增益可读写")
    assertClose(saved.duration, 0.3, "时长可读写")
    assertClose(saved.minStep, 0.25, "步长可读写")
    assertEqual(saved.reverseDirection, true, "反向可读写")

    // 越界写入按区间收敛（不把非法值落盘）
    settings.setSpeedGain(99)
    assertEqual(settings.parameters.speedGain, SmoothScrollParameters.speedGainRange.upperBound,
                "越界增益落盘前收敛")
    settings.setDuration(.nan)
    assertEqual(settings.parameters.duration, SmoothScrollParameters.defaultDuration,
                "NaN 时长落盘为默认值")
    settings.setMinStep(0)
    assertEqual(settings.parameters.minStep, SmoothScrollParameters.minStepRange.lowerBound,
                "0 步长收敛到下界")

    // 手改坏的存储值（绕过 setter 直接写）也读成默认
    let hostile = InMemoryStorage()
    hostile.set(0.0, forKey: SmoothScrollPreferenceKey.speedGain)
    hostile.set(-5.0, forKey: SmoothScrollPreferenceKey.duration)
    let hostileSettings = SmoothScrollSettings(storage: hostile)
    assertEqual(hostileSettings.parameters.speedGain, SmoothScrollParameters.defaultSpeedGain,
                "存储里是 0 时回落默认增益")
    assertEqual(hostileSettings.parameters.duration, SmoothScrollParameters.defaultDuration,
                "存储里是负数时时长回落默认")
}

// MARK: - 断言辅助

private func assertClose(_ actual: Double,
                         _ expected: Double,
                         tolerance: Double = 1e-9,
                         _ message: String = "",
                         file: String = #file,
                         line: Int = #line) {
    if abs(actual - expected) <= tolerance {
        print("✅ \(message)（\(actual)）")
        return
    }
    let detail = "\(file):\(line) — expected \(expected) ± \(tolerance), got \(actual)"
        + (message.isEmpty ? "" : " — \(message)")
    print("❌ \(detail)")
    TestAssertions.recordFailure(detail)
}
