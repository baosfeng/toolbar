import CoreGraphics

// MARK: - 标注颜色透明度

public extension SnipAnnotationColor {

    /// 派生一个改变透明度后的颜色（alpha 夹到 0…1）
    ///
    /// Snipaste「高级技巧」：点击工具条上的大颜色按钮可改其 Alpha 通道（0–255）。
    /// 颜色本身是不可变值类型，透明度调整统一走这个派生入口，
    /// 免得调用方到处写 SnipAnnotationColor(red:green:blue:alpha:) 把分量抄漏。
    func withAlpha(_ alpha: CGFloat) -> SnipAnnotationColor {
        SnipAnnotationColor(red: red,
                            green: green,
                            blue: blue,
                            alpha: min(max(alpha, 0), 1))
    }
}
