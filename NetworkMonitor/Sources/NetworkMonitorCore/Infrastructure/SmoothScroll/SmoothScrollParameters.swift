import Foundation

// MARK: - 平滑参数

/// 鼠标滚轮平滑的参数模型 —— 纯值、可归一化
///
/// 四个可调项对应设置页四个控件（开关 / 速度增益 / 持续时间 / 最短步长）加上反向滚动；
/// 区间与默认值都定义在这里：设置页滑块、引擎与测试读同一份口径，
/// 不出现「界面允许 5 倍、引擎按 2 倍截断」这类两套真值。
///
/// 缺键回落默认值（关闭）：老用户升级后行为完全不变，必须显式打开才生效。
public struct SmoothScrollParameters: Sendable, Equatable {

    /// 总开关（默认关）
    public var enabled: Bool
    /// 速度增益（倍）
    public var speedGain: Double
    /// 一次滚轮事件拆完的最长跨度（秒）
    public var duration: Double
    /// 最短步长（行）：单个回投事件至少走这么多，决定一次事件最多拆几帧
    public var minStep: Double
    /// 反向滚动
    public var reverseDirection: Bool

    // MARK: 默认值与区间（设置页滑块与引擎共用）

    public static let defaultEnabled = false
    public static let defaultSpeedGain = 1.0
    public static let defaultDuration = 0.18
    public static let defaultMinStep = 0.5
    public static let defaultReverseDirection = false

    public static let speedGainRange = 0.3...3.0
    public static let durationRange = 0.04...0.40
    public static let minStepRange = 0.10...3.0

    public init(enabled: Bool = SmoothScrollParameters.defaultEnabled,
                speedGain: Double = SmoothScrollParameters.defaultSpeedGain,
                duration: Double = SmoothScrollParameters.defaultDuration,
                minStep: Double = SmoothScrollParameters.defaultMinStep,
                reverseDirection: Bool = SmoothScrollParameters.defaultReverseDirection) {
        self.enabled = enabled
        self.speedGain = speedGain
        self.duration = duration
        self.minStep = minStep
        self.reverseDirection = reverseDirection
    }

    /// 缺省参数（开关关闭）
    public static let defaults = SmoothScrollParameters()

    // MARK: 归一化

    /// 归一化后的参数 —— 越界按区间收敛、NaN / 无穷回落到默认值
    ///
    /// 引擎与设置页一律用归一化后的值：偏好被手改成 1e9 或 NaN 时，
    /// 宁可退回默认，也不让一帧算出巨量位移或死循环。
    public var clamped: SmoothScrollParameters {
        SmoothScrollParameters(enabled: enabled,
                               speedGain: Self.clamp(speedGain,
                                                     to: Self.speedGainRange,
                                                     fallback: Self.defaultSpeedGain),
                               duration: Self.clamp(duration,
                                                    to: Self.durationRange,
                                                    fallback: Self.defaultDuration),
                               minStep: Self.clamp(minStep,
                                                   to: Self.minStepRange,
                                                   fallback: Self.defaultMinStep),
                               reverseDirection: reverseDirection)
    }

    /// 方向系数（反向滚动时为 −1）
    public var directionSign: Double { reverseDirection ? -1 : 1 }

    /// 原始增量按速度增益与方向换算成要回投的总位移
    public func scaledDelta(_ delta: Double) -> Double {
        guard delta.isFinite else { return 0 }
        return delta * clamped.speedGain * clamped.directionSign
    }

    private static func clamp(_ value: Double,
                              to range: ClosedRange<Double>,
                              fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - 增量拆分

/// 增量拆分纯函数 —— 把一次滚轮增量切成若干「步」
///
/// 只做两件事：按 `step` 的上界决定段数、等分并保证 **和恰好等于原增量**
/// （最后一段吃掉浮点余量），因此拆分前后位移总量一致，不会出现累积漂移。
/// 段数有上限（`maximumSteps`）：偏好被改成 NaN 或增量异常大时也不会生成海量事件。
public enum SmoothScrollSplitter {

    /// 单次滚轮最多拆成多少段（= 最多回投多少个事件）
    public static let maximumSteps = 120

    /// 拆分增量
    ///
    /// - Parameters:
    ///   - delta: 原始增量（正负皆可；0 / NaN / 无穷 → 空数组）
    ///   - step: 单段上界（非有限或 ≤0 时按 1 处理）
    /// - Returns: 同号的等分增量数组，Σ == delta
    public static func split(delta: Double, step: Double) -> [Double] {
        guard delta.isFinite, delta != 0 else { return [] }
        let unit = (step.isFinite && step > 0) ? step : 1
        let rawCount = (abs(delta) / unit).rounded(.up)
        let count = min(max(Int(rawCount), 1), maximumSteps)
        guard count > 1 else { return [delta] }
        let piece = delta / Double(count)
        var steps = [Double](repeating: piece, count: count - 1)
        // 最后一段吃掉浮点余量：Σ 恒等于 delta（否则逐帧回投会慢慢偏）
        steps.append(delta - piece * Double(count - 1))
        return steps
    }
}

// MARK: - 帧序列

/// 帧序列推导 —— 一次滚轮增量 → 逐帧回投的位移
///
/// 帧数由两个上界取小：`minStep` 决定的拆分段数（**密度上界**：每帧至少走一步）、
/// `duration × 刷新率` 决定的帧数（**跨度上界**：整段动画最多跨这么久）。
/// 帧数定下来后，位移比例由 `SmoothScrollCurve.weights` 按曲线分配，Σ == 总位移。
///
/// 纯函数、无 AppKit：TestRunner 直接断言帧数上界与位移守恒。
public enum SmoothScrollMotion {

    /// 推导逐帧位移（`parameters` 关闭时返回空数组 = 不平滑）
    public static func frameDeltas(delta: Double,
                                   parameters: SmoothScrollParameters,
                                   framesPerSecond: Double) -> [Double] {
        let resolved = parameters.clamped
        let total = resolved.scaledDelta(delta)
        let weights = weights(delta: delta, parameters: resolved, framesPerSecond: framesPerSecond)
        return weights.map { total * $0 }
    }

    /// 逐帧位移权重（Σ == 1；关掉或增量为 0 时返回空数组）
    ///
    /// 引擎按这一份权重给两条轴同时分配：主轴与副轴共用同一组曲线权重，
    /// 斜向滚轮不会出现两轴速度不一致的「拧」感。
    public static func weights(delta: Double,
                               parameters: SmoothScrollParameters,
                               framesPerSecond: Double) -> [Double] {
        let resolved = parameters.clamped
        guard resolved.enabled, resolved.scaledDelta(delta) != 0 else { return [] }
        let count = frameCount(delta: delta, parameters: resolved, framesPerSecond: framesPerSecond)
        return SmoothScrollCurve.weights(count: count)
    }

    /// 帧数（至少 1；关掉时也返回 1，调用方按 `frameDeltas` 判断是否需要动画）
    public static func frameCount(delta: Double,
                                  parameters: SmoothScrollParameters,
                                  framesPerSecond: Double) -> Int {
        let resolved = parameters.clamped
        let total = resolved.scaledDelta(delta)
        guard total != 0 else { return 1 }
        let steps = SmoothScrollSplitter.split(delta: total, step: resolved.minStep).count
        let fps = (framesPerSecond.isFinite && framesPerSecond > 0)
            ? min(max(framesPerSecond, 24), 240)
            : 60
        let durationFrames = max(1, Int((resolved.duration * fps).rounded()))
        return max(1, min(steps, durationFrames))
    }
}
