import CoreGraphics
import Foundation

// MARK: - 标注颜色 hex 编码

/// 颜色 → 偏好用的 hex 字符串
///
/// 设置页把「默认颜色」以 hex 存进偏好，覆盖层里换过颜色后也要按同一格式回写，
/// 否则设置页读不到、调色板高亮会落空（两边格式不一致是这类「设了不生效」的常见成因）。
///
/// **alpha 必须一起编**：二级面板能调颜色透明度，但早期只写 #RRGGBB，
/// 于是「调好的半透明笔」下次截图又回到不透明 —— 用户视角就是「设置存不住」。
/// 不透明时仍输出 6 位（既有偏好、设置页调色板比对都不受影响）。
public enum SnipAnnotationColorHex {

    /// 颜色 → #RRGGBB（不透明）或 #RRGGBBAA（带透明度）
    public static func hex(_ color: SnipAnnotationColor) -> String {
        let r = channel(color.red)
        let g = channel(color.green)
        let b = channel(color.blue)
        if color.alpha < 0.999 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, channel(color.alpha))
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// 颜色 → #RRGGBB（永远 6 位，丢掉透明度）
    ///
    /// 调色板比对 / 设置页高亮都用这一份：`hex` 可能带 alpha，
    /// 拿它去比调色板会让「半透明的红」被认成自定义色。
    public static func rgbHex(_ color: SnipAnnotationColor) -> String {
        String(format: "#%02X%02X%02X",
               channel(color.red), channel(color.green), channel(color.blue))
    }

    /// 分量 → 0…255
    private static func channel(_ value: CGFloat) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }
}
