import CoreGraphics
import Foundation

// MARK: - 标注默认样式（偏好 → 初始样式）

/// 把偏好里的颜色 / 线宽 / 线型解析成一次截图开工时的初始样式
///
/// 背景：设置页早就写入了 annotationColor / annotationLineWidth 两个键，但全仓没有消费方 ——
/// 用户改「默认颜色 / 线宽」对新建截图**完全不生效**（与快捷键被还原是同一类「设了没用」的毛病）。
/// 解析口径收进这个纯函数，界面层与设置页共用同一份默认值，不再各写一遍。
public enum SnipAnnotationStyleResolver {

    /// 设置页调色板里第一档（红色）的 hex，与设置页 defaultColorHex 同一取值
    public static let defaultColorHex = "#EB3330"
    /// 默认线宽（与设置页「中」档一致）
    public static let defaultLineWidth: CGFloat = 4

    /// 解析初始样式
    ///
    /// - Parameters:
    ///   - colorHex: 偏好里的颜色 hex（未设置或解析不出时回落默认红）
    ///   - lineWidth: 偏好里的线宽（未设置时回落默认值，异常值夹到可选范围）
    ///   - dashed: 偏好里的线型（默认实线）
    ///   - text: 文字样式（字号 / 字重 / 字体族）；缺省时沿用旧口径「字号由线宽推导」
    /// - Parameter effect: 马赛克 / 模糊强度；缺省值 14/14，与既有常量一致
    public static func style(colorHex: String?,
                             lineWidth: CGFloat?,
                             dashed: Bool,
                             text: SnipTextStyle = SnipTextStyle(),
                             effect: SnipEffectStyle = SnipEffectStyle()) -> SnipAnnotationStyle {
        let color = color(fromHex: colorHex) ?? .red
        var width = lineWidth.map { min(max($0, 1), 40) } ?? defaultLineWidth
        width = SnipLineWidthRange.clamp(width)
        return SnipAnnotationStyle(color: color, lineWidth: width, dashed: dashed,
                                   text: text, effect: effect)
    }

    /// hex → 颜色；接受 #RRGGBB 与 #RRGGBBAA（含或不含前导 #），其余一律视为无效
    ///
    /// 8 位形式的引入原因：颜色透明度过去只存在于二级面板，回写偏好时只写 RGB，
    /// 于是「调好的半透明笔」下次截图又变成不透明。带上 alpha 才谈得上持久化。
    public static func color(fromHex hex: String?) -> SnipAnnotationColor? {
        guard let hex else { return nil }
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        let value = UInt32(text, radix: 16) ?? 0
        let hasAlpha = text.count == 8
        let red = (value >> (hasAlpha ? 24 : 16)) & 0xFF
        let green = (value >> (hasAlpha ? 16 : 8)) & 0xFF
        let blue = (value >> (hasAlpha ? 8 : 0)) & 0xFF
        let alpha = hasAlpha ? value & 0xFF : 0xFF
        return SnipAnnotationColor(red: CGFloat(red) / 255,
                                   green: CGFloat(green) / 255,
                                   blue: CGFloat(blue) / 255,
                                   alpha: CGFloat(alpha) / 255)
    }
}

// MARK: - 线宽范围（Core 侧唯一口径）

/// 线宽上下限 —— UI 与渲染 / 解析共用的同一份范围
///
/// 放在 Core 是因为解析器要用它夹值，而 UI 目标里的 SnipLineWidthStepper
/// 也引用它：两边各写一遍 1...40 迟早分叉。
public enum SnipLineWidthRange {
    public static let range: ClosedRange<CGFloat> = 1...40

    public static func clamp(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return 4 }
        return min(max(width, range.lowerBound), range.upperBound)
    }
}
