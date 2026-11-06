import AppKit

// MARK: - 额度页小图表（进度条 / 迷你走势）

/// 3pt 细进度条 —— 剩余比例分级着色
///
/// 分级色走 `PaneCardStyle` 的墨色档（与状态胶囊、告警文字同源），不另引系统色。
final class BillingProgressBarView: NSView {

    /// 告警级别
    enum Level {
        case normal
        case warn
        case danger
    }

    /// 条高
    static let preferredHeight: CGFloat = 3

    private var fraction: Double = 0
    private var level: Level = .normal

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    func update(fraction: Double, level: Level) {
        self.fraction = min(max(fraction, 0), 1)
        self.level = level
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = max(bounds.height / 2, 1)
        PaneCardStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard fraction > 0 else { return }
        let width = max(bounds.height, bounds.width * fraction)
        let fillRect = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }

    private var fillColor: NSColor {
        switch level {
        case .normal: return PaneCardStyle.okColor
        case .warn:   return PaneCardStyle.warnInk
        case .danger: return PaneCardStyle.requestColor
        }
    }
}
