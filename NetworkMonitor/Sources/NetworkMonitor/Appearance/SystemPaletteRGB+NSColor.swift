import AppKit
import NetworkMonitorCore

// MARK: - 纯值色 → AppKit 色（App 目标专用）

/// `SystemPaletteRGB` 是 Core / UI 目标的纯值色（不依赖 AppKit），
/// 视图要画它时在这里一次性转成 sRGB `NSColor`，不各页各写一套换算。
extension SystemPaletteRGB {

    /// sRGB 实色（自绘取 `cgColor` 时也走这条路径，保证与断言用的色值同源）
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1)
    }
}
