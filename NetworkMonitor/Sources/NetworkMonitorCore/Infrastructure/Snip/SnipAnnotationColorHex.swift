import CoreGraphics
import Foundation

// MARK: - 标注颜色 hex 编码

/// 颜色 → 设置页调色板用的 hex 字符串（#RRGGBB，大写）
///
/// 设置页把「默认颜色」以 hex 存进偏好，覆盖层里换过颜色后也要按同一格式回写，
/// 否则设置页读不到、调色板高亮会落空（两边格式不一致是这类「设了不生效」的常见成因）。
public enum SnipAnnotationColorHex {

    /// 颜色 → #RRGGBB
    public static func hex(_ color: SnipAnnotationColor) -> String {
        let r = Int((min(max(color.red, 0), 1) * 255).rounded())
        let g = Int((min(max(color.green, 0), 1) * 255).rounded())
        let b = Int((min(max(color.blue, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
