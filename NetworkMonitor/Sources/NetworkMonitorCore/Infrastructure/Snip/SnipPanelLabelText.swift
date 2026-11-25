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

    /// 字号文案（如「20 pt」）—— 与线宽同一套取整规则，避免 20 与 20.0 两种写法并存
    public static func size(_ value: CGFloat) -> String {
        width(value)
    }

    /// 透明度文案
    public static func alpha(_ value: CGFloat) -> String {
        switch value {
        case ..<0.45: return "淡"
        case ..<0.8: return "半透明"
        default: return "不透明"
        }
    }

    // MARK: - 选区尺寸标签

    /// 选区尺寸标签文案，形如「548 x 286」
    ///
    /// 分隔符刻意用 ASCII 小写 `x` 而不是乘号 U+00D7：标签用等宽数字字体，
    /// 乘号与数字的字宽不一致，宽高变化时读数会左右抖一下。
    public static func size(width: CGFloat, height: CGFloat) -> String {
        "\(Int(width.rounded())) x \(Int(height.rounded()))"
    }

    /// 尺寸标签指向选区的 4pt 三角（三点，顺序：顶点 / 左底 / 右底）
    ///
    /// 三角夹在标签与选区之间：顶点压在选区上边界，底边贴着标签。
    /// 标签贴在选区上方时三角朝下；标签翻进选区内部时朝上——两种情况顶点都咬住选区上边界。
    ///
    /// 三角必须画在标签矩形外：`sizeLabelFrame` 是「点它就进尺寸输入」的命中区，
    /// 把三角算进去等于让用户点三角也弹输入框。
    public static func sizeLabelArrowPoints(pointingDown: Bool,
                                            labelFrame: CGRect,
                                            selection: CGRect,
                                            height: CGFloat = 4) -> [CGPoint] {
        guard height > 0, selection.width >= 1, selection.height >= 1 else { return [] }
        // 底边半宽取高度的 1.5 倍（4pt 高 → 12pt 底），但不宽于选区，免得小选区上箭头比选区还宽
        let halfBase = min(height * 1.5, selection.width / 2)
        // 水平居中于标签，再夹进选区水平范围：标签贴边界时三角也不伸到选区外
        let centerX = min(max(labelFrame.midX, selection.minX + halfBase), selection.maxX - halfBase)
        let apexY = selection.minY
        let baseY = pointingDown ? apexY - height : apexY + height
        return [CGPoint(x: centerX, y: apexY),
                CGPoint(x: centerX - halfBase, y: baseY),
                CGPoint(x: centerX + halfBase, y: baseY)]
    }
}
