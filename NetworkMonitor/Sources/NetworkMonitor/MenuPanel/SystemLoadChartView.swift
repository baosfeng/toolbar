import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 负载三线

/// 负载三线折线 — 1 / 5 / 15 分钟均值 + 核数参考虚线（近 60 秒）
///
/// **量程不是固定 0–100%**：负载是就绪队列长度（可以远超核数），纵轴上限按
/// `cap = max(核数 × 1.2, 峰值 × 1.15)` 现算；核数参考线按 `核数 / cap` 的真实比例画，
/// 所以「三线越过虚线」直接读作「有进程在排队」，而不是靠刻度猜。
final class SystemLoadChartView: NSView {

    /// 1 分钟序列（主序列，最粗实线）
    var shortValues: [Double] = [] {
        didSet {
            guard shortValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 5 分钟序列
    var mediumValues: [Double] = [] {
        didSet {
            guard mediumValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 15 分钟序列（虚线细）
    var longValues: [Double] = [] {
        didSet {
            guard longValues != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 逻辑核数（参考虚线的真实位置；0 表示不画参考线）
    var coreCount: Int = 0 {
        didSet {
            guard coreCount != oldValue else { return }
            needsDisplay = true
        }
    }

    /// 纵轴上限（由调用方按 cap 公式现算；≤0 时按峰值兜底）
    var axisMaximum: Double = 0 {
        didSet { needsDisplay = true }
    }

    init(height: CGFloat = 34) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 固定高度 + 纵向抗拉伸：压力卡是纵向 stack，默认会把图表拉满剩余空间，
        // 三条线被摊到整行高后贴在底边（实测图上「三线挤成一条」就是这个原因）
        let fixed = heightAnchor.constraint(equalToConstant: height)
        fixed.priority = .required
        fixed.isActive = true
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setAccessibilityRole(.image)
        setAccessibilityLabel("近 60 秒系统负载三线")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 绘制只留一份（SystemChartDrawing）：自绘卡片复用同一个函数，两条路径不会画出两种图
        SystemChartDrawing.drawLoadChart(short: shortValues, medium: mediumValues,
                                         long: longValues, coreCount: coreCount,
                                         axisMaximum: axisMaximum, in: bounds,
                                         shortColor: SystemPaneStyle.loadShort,
                                         mediumColor: SystemPaneStyle.loadMedium,
                                         longColor: SystemPaneStyle.loadLong,
                                         referenceColor: SystemPaneStyle.loadCoreReference,
                                         trackColor: SystemPalette.track)
    }

    /// 量程口径（供卡头 toolTip 与测试共用）：`max(核数 × 1.2, 峰值 × 1.15)`
    ///
    /// 下限用核数保证「低负载时不要把噪声放大成满画布」，上限用峰值让三条线用满高度。
    static func axisMaximum(coreCount: Int, peak: Double) -> Double {
        SystemCardLayout.loadAxisMaximum(coreCount: coreCount, peak: peak)
    }
}
