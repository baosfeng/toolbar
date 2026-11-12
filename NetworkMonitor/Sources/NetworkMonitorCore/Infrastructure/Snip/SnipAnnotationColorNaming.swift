import CoreGraphics
import Foundation

// MARK: - 标注颜色名称

/// 调色板颜色的中文名 —— 悬停气泡与设置页共用同一份口径
///
/// 颜色是浮点分量，直接比 Equatable 会在「改过透明度」后失配；
/// 因此按 #RRGGBB 的 hex 比对（忽略 alpha），并留「自定义」兜底。
public enum SnipAnnotationColorNaming {

    /// 调色板七档，顺序即颜色面板顺序
    public static let palette: [(hex: String, name: String)] = [
        ("#EB3330", "红色"),
        ("#F58C24", "橙色"),
        ("#FAD12E", "黄色"),
        ("#33B859", "绿色"),
        ("#2980F2", "蓝色"),
        ("#1A1A1A", "黑色"),
        ("#FFFFFF", "白色"),
    ]

    /// 颜色 → 中文名；不在调色板里时返回「自定义色」
    public static func name(for color: SnipAnnotationColor) -> String {
        let hex = SnipAnnotationColorHex.hex(color)
        return palette.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "自定义色"
    }

    /// hex → 中文名（设置页按存储里的 hex 直接取名）
    public static func name(forHex hex: String?) -> String {
        guard let hex else { return "自定义色" }
        return palette.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name ?? "自定义色"
    }
}
