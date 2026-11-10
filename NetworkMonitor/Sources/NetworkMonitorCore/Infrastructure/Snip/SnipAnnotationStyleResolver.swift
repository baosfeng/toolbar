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
    ///   - lineWidth: 偏好里的线宽（未设置时回落默认值，异常值夹到 1...40）
    ///   - dashed: 偏好里的线型（默认实线）
    public static func style(colorHex: String?,
                             lineWidth: CGFloat?,
                             dashed: Bool) -> SnipAnnotationStyle {
        let color = color(fromHex: colorHex) ?? .red
        let width = lineWidth.map { min(max($0, 1), 40) } ?? defaultLineWidth
        return SnipAnnotationStyle(color: color, lineWidth: width, dashed: dashed)
    }

    /// hex → 颜色；只接受 #RRGGBB（含或不含前导 #），其余一律视为无效
    public static func color(fromHex hex: String?) -> SnipAnnotationColor? {
        guard let hex else { return nil }
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy({ $0.isHexDigit }) else { return nil }
        let value = UInt32(text, radix: 16) ?? 0
        return SnipAnnotationColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                                   green: CGFloat((value >> 8) & 0xFF) / 255,
                                   blue: CGFloat(value & 0xFF) / 255)
    }
}
