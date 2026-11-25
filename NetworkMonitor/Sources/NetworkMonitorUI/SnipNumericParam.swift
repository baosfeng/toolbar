import CoreGraphics
import Foundation

// MARK: - 数值参数（截图标注里的"一根旋钮"）

/// 截图 / 标注里所有可调数值的统一描述
///
/// 背景：这些参数此前各自散落在三处硬编码档位表里（线宽 `[2,4,8]`、字号 6 档、
/// 透明度 3 档），而值本身早就是 `CGFloat`。用户说"只能调 6 个"，根因不是值域窄，
/// 是**入口离散**。这里把它们收成一张表：范围 / 最小单位 / 默认值 / 单位 / 显示格式
/// 只有一份，步进、输入框、HUD、设置页都从这里取，不再各写一遍。
///
/// 放在 UI target 而不是 Core：显示格式与单位后缀是展示口径，TestRunner 可以直接断言。
public enum SnipNumericParam: String, CaseIterable, Equatable, Sendable {

    /// 画笔线宽（pt）—— 描边粗细
    case lineWidth
    /// 文字字号（pt）—— 与线宽解耦的另一根旋钮
    case fontSize
    /// 标注颜色透明度（0…1，显示为百分比）
    case opacity
    /// 马赛克块边长（px）
    case mosaicBlock
    /// 高斯模糊半径（px）
    case blurRadius
    /// 放大镜放大倍数
    case magnifierZoom

    // MARK: - 值域

    /// 允许范围（含端点）
    ///
    /// 上限一律沿用本仓既有口径，不新造：线宽 1…40 来自 `SnipLineWidthRange`，
    /// 字号 9…160 来自 `SnipTextStyle.fontSizeRange`，透明度是 0…1 的正常化值。
    public var range: ClosedRange<CGFloat> {
        switch self {
        case .lineWidth: return 1...40
        case .fontSize: return 9...160
        case .opacity: return 0...1
        case .mosaicBlock: return 2...32
        case .blurRadius: return 1...40
        case .magnifierZoom: return 2...16
        }
    }

    /// 一个「最小单位」—— 滚轮一格、按一次键的默认步长
    ///
    /// 取值原则：调到最细仍有意义。1pt 的线宽差肉眼可辨，1% 的透明度差可辨，
    /// 而 0.1pt 的线宽在 Retina 上已经是亚像素，调了看不出变化只会让人觉得"没反应"。
    public var minimumUnit: CGFloat {
        switch self {
        case .lineWidth: return 1
        case .fontSize: return 1
        case .opacity: return 0.05
        case .mosaicBlock: return 1
        case .blurRadius: return 1
        case .magnifierZoom: return 1
        }
    }

    /// 量化粒度：最小单位的一半，让 ⌥ 精调能落在两档之间
    ///
    /// 线宽 1pt 的最小单位 → 0.5pt 的量化粒度，⌥ 一次走 0.5pt；
    /// 透明度 5% 的最小单位 → 2.5% 的量化粒度。显示时再按 `decimals` 取整。
    public var quantum: CGFloat { minimumUnit / 2 }

    /// 缺省值（用户没存过偏好时用它）
    ///
    /// 与各模块既有的缺省值保持一致：线宽 4、字号 20、透明度 1（不透明）、
    /// 马赛克与模糊 14（`SnipMosaicProcessor` 的既有常量）、放大镜 8（120pt ÷ 15pt 跨度）。
    public var defaultValue: CGFloat {
        switch self {
        case .lineWidth: return 4
        case .fontSize: return 20
        case .opacity: return 1
        case .mosaicBlock: return 14
        case .blurRadius: return 14
        case .magnifierZoom: return 8
        }
    }

    // MARK: - 显示口径

    /// 单位后缀（百分比参数留空，由 `format` 自己拼 `%`）
    public var unitSuffix: String {
        switch self {
        case .lineWidth, .fontSize: return "pt"
        case .mosaicBlock, .blurRadius: return "px"
        case .magnifierZoom: return "×"
        case .opacity: return ""
        }
    }

    /// 中文名（HUD、设置页行名、无障碍标签共用）
    public var displayName: String {
        switch self {
        case .lineWidth: return "线宽"
        case .fontSize: return "字号"
        case .opacity: return "透明度"
        case .mosaicBlock: return "马赛克粒度"
        case .blurRadius: return "模糊强度"
        case .magnifierZoom: return "放大倍数"
        }
    }

    /// 中文名（追加副文本时用短名，HUD 一行放得下）
    public var shortDisplayName: String {
        switch self {
        case .lineWidth: return "线宽"
        case .fontSize: return "字号"
        case .opacity: return "透明度"
        case .mosaicBlock: return "马赛克"
        case .blurRadius: return "模糊"
        case .magnifierZoom: return "放大"
        }
    }

    /// 显示小数位：百分比与半档线宽要带小数，其余取整
    public var decimals: Int {
        switch self {
        case .lineWidth, .fontSize: return 1
        case .opacity: return 0
        case .mosaicBlock, .blurRadius, .magnifierZoom: return 0
        }
    }

    /// 格式化一个值（HUD 与工具条常显共用这一份，避免两处出现 `12` 与 `12.0`）
    ///
    /// - 整数就写整数（`12 pt`），半档才写一位小数（`12.5 pt`）；
    /// - 透明度写成百分比（`60%`），不写 `0.6`——用户脑子里想的是百分比。
    public func format(_ value: CGFloat) -> String {
        let clamped = clampValue(value)
        if self == .opacity {
            return "\(Int((clamped * 100).rounded()))%"
        }
        let rounded = (clamped * 10).rounded() / 10
        let number = rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
        return unitSuffix.isEmpty ? number : "\(number) \(unitSuffix)"
    }

    // MARK: - 夹取

    /// 把任意值夹进范围（NaN / 无穷回落缺省值）
    public func clampValue(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// 夹取后按量化粒度对齐（避免 `12.0000001` 这类浮点尾巴进偏好）
    public func quantized(_ value: CGFloat) -> CGFloat {
        let clamped = clampValue(value)
        let unit = quantum
        guard unit > 0 else { return clamped }
        let steps = (clamped / unit).rounded()
        return clampValue(steps * unit)
    }
}
