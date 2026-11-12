import CoreGraphics
import Foundation

// MARK: - 二级面板的条目文案

/// 二级面板（工具 / 颜色 / 线宽 / 画笔样式）的条目文字 —— 面板与设置页共用一份口径
///
/// 面板此前完全靠图形表达（色点、粗细条、透明度圆点），新用户看不出点的是什么；
/// 文案收进 Core 纯函数，面板绘制与测试断言同源。
public enum SnipPanelLabelText {

    /// 线宽档文案（如「4 pt」）
    public static func width(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) pt"
            : String(format: "%.1f pt", rounded)
    }

    /// 线型文案
    public static func dash(_ dashed: Bool) -> String {
        dashed ? "虚线" : "实线"
    }

    /// 透明度文案
    public static func alpha(_ value: CGFloat) -> String {
        switch value {
        case ..<0.45: return "淡"
        case ..<0.8: return "半透明"
        default: return "不透明"
        }
    }
}
