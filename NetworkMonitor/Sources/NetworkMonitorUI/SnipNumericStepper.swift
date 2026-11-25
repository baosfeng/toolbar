import CoreGraphics
import Foundation

// MARK: - 数值步进（纯逻辑，可单测）

/// 把一个数值按「意图」推进若干步 —— 所有滚轮 / 按键 / 面板 −+ 共用的唯一实现
///
/// 之前这个逻辑散在两处：`SnipLineWidthStepper.step`（档位吸附）与
/// `SnipLineWidthStepper.continuousStep`（连续），字号又是第三份
/// `SnipTextStyle.steppedFontSize`。三份实现意味着三套手感，用户换个参数就得重新适应。
/// 现在只有这一份：范围、最小单位、量化粒度都来自 `SnipNumericParam`。
public enum SnipNumericStepper {

    /// 推进一个值
    ///
    /// - Parameters:
    ///   - value: 当前值（可以是任意浮点，不必落在档位上）
    ///   - param: 参数定义（范围 / 最小单位 / 量化粒度）
    ///   - steps: 前进几步（正 = 变大，负 = 变小）；0 表示只做夹取与量化
    ///   - intent: 调整意图（coarse / fine / fast）
    /// - Returns: 夹取并量化后的新值
    public static func step(_ value: CGFloat,
                            param: SnipNumericParam,
                            steps: Int,
                            intent: SnipNumericIntent = .coarse) -> CGFloat {
        let base = param.clampValue(value)
        guard steps != 0 else { return param.quantized(base) }
        let stride = stepSize(param: param, intent: intent)
        let next = base + CGFloat(steps) * stride
        return param.quantized(next)
    }

    /// 单步步长（已按意图换算）
    ///
    /// 精调取最小单位的一半，再与量化粒度取大者 —— 否则线宽 1pt 的最小单位下
    /// 精调会得到 0.5pt，而量化粒度正好也是 0.5pt，两者一致；透明度 0.05 的最小单位下
    /// 精调 0.025 = 量化粒度 0.025，同样一致。取大者是为了将来改其中一个常量时不出空步。
    public static func stepSize(param: SnipNumericParam, intent: SnipNumericIntent) -> CGFloat {
        switch intent {
        case .coarse: return param.minimumUnit
        case .fine: return max(param.minimumUnit * SnipNumericIntent.fineRatio, param.quantum)
        case .fast: return param.minimumUnit * SnipNumericIntent.fastMultiplier
        }
    }

    /// 直接设一个绝对值（输入框 / 双击复位用），夹取 + 量化
    public static func set(_ value: CGFloat, param: SnipNumericParam) -> CGFloat {
        param.quantized(value)
    }

    /// 值是否已经贴到上下限（面板 −/+ 与按键据此决定要不要把操作"吃掉"）
    ///
    /// 用法：已经在 40pt 时再按加粗应当返回 false，让调用方放行按键，
    /// 而不是吞掉一个什么都不做的按键（吞键会让用户以为按键失效）。
    public static func isAtLimit(_ value: CGFloat, param: SnipNumericParam) -> Bool {
        let clamped = param.clampValue(value)
        return clamped <= param.range.lowerBound + 0.0001
            || clamped >= param.range.upperBound - 0.0001
    }
}
