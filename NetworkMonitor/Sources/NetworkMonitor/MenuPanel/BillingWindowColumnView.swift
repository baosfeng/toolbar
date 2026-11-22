import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 额度窗口列（自绘）

/// 一列额度 —— 「百分比（13pt 粗等宽）+ 3pt 细条 + 重置行（8.5pt）」一次画完
///
/// 版式来自原型 F1 的总表格：百分比是这一屏的信息主体（13pt 粗等宽），
/// 条只做强弱体感（3pt，与改造前额度格同高），重置行把「窗口名 · 何时重置」并进一行，
/// 这样一行 provider 只占 34pt 就能读完成两三个窗口。
///
/// 两档字号：总表用 13pt（detail 为 false），覆盖式二级页用 19pt（detail 为 true），
/// 同一套绘制代码，避免二级页再写一遍另一种排版。
@MainActor
final class BillingWindowColumnView: NSView {

    /// 一列的绘制数据
    struct Spec: Equatable {
        var title: String
        var remaining: Double?
        var resetsAt: Date?
        var badge: String?

        init(title: String, remaining: Double?, resetsAt: Date?, badge: String? = nil) {
            self.title = title
            self.remaining = remaining
            self.resetsAt = resetsAt
            self.badge = badge
        }
    }

    /// 窄列档（三列时每列约 59pt）：重置行省掉「重置」二字，只留时分
    var isCompact = false {
        didSet {
            guard isCompact != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// 是否二级页大字号档
    var isDetail = false {
        didSet {
            guard isDetail != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private(set) var spec: Spec? {
        didSet {
            guard spec != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            setAccessibilityLabel(spec.map(Self.accessibilityText))
            toolTip = spec.map(Self.accessibilityText)
        }
    }

    /// 进度条高度（与改造前额度格同值，3pt）
    static let barHeight: CGFloat = 3
    /// 行距
    private static let spacing: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 自上而下排版
    override var isFlipped: Bool { true }

    // MARK: - 数据

    func update(_ spec: Spec?) {
        self.spec = spec
    }

    func clear() { spec = nil }

    // MARK: - 尺寸

    static func valueFont(detail: Bool, compact: Bool = false) -> NSFont {
        if detail { return PaneCardStyle.cardValueFont }
        return compact ? Self.denseValueFont : Self.tableValueFont
    }

    /// 表格里的百分比：13pt 粗等宽（原型实测 13pt 是「一行读得清、又塞得进 86pt 列」的档位）
    static let tableValueFont: NSFont = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
    /// 三列窄格里的百分比：12pt（52pt 列宽下 13pt 会让「100 %」贴边）
    static let denseValueFont: NSFont = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)

    /// 重置行字号（8.5pt 等宽，与坐标轴同档）
    static let resetFont: NSFont = PaneCardStyle.axisFont

    override var intrinsicContentSize: NSSize {
        guard let spec else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: Self.contentHeight(spec, detail: isDetail, compact: isCompact))
    }

    /// 一列的内容总高（绘制与尺寸共用同一份口径）
    static func contentHeight(_ spec: Spec, detail: Bool, compact: Bool = false) -> CGFloat {
        var height = valueLineHeight(detail: detail, compact: compact) + spacing + barHeight
        if !resetText(spec, compact: compact).isEmpty {
            height += spacing + DrawnTextRun(string: "0", font: resetFont,
                                             color: PaneCardStyle.tertiaryText).lineHeight
        }
        return height
    }

    private static func valueLineHeight(detail: Bool, compact: Bool) -> CGFloat {
        DrawnTextRun(string: "100", font: valueFont(detail: detail, compact: compact),
                     color: PaneCardStyle.primaryText).lineHeight
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let spec, bounds.width > 0 else { return }
        let font = Self.valueFont(detail: isDetail, compact: isCompact)
        let split = PaneValueFormatting.split(formatPercentCompact(spec.remaining))
        let valueRun = DrawnTextRun(string: split.number, font: font,
                                    color: Self.valueColor(spec.remaining))
        let unitText = split.unit.isEmpty ? "%" : split.unit
        let unitRun = DrawnTextRun(string: unitText,
                                   font: PaneCardStyle.cardValueUnitFont,
                                   color: PaneCardStyle.tertiaryText)

        // 第一行：百分比 + 单位（共用基线）
        var y: CGFloat = 0
        let baseline = valueRun.font.ascender
        valueRun.draw(baselineAt: baseline, x: 0, width: bounds.width)
        if !unitText.isEmpty {
            let unitX = min(valueRun.width() + PaneValueFormatting.gap, bounds.width)
            unitRun.draw(baselineAt: baseline, x: unitX, width: max(bounds.width - unitX, 1))
        }
        y += valueRun.lineHeight + Self.spacing

        // 第二行：3pt 细条（不可得不画填充）
        DrawnInk.fill(CGRect(x: 0, y: y, width: bounds.width, height: Self.barHeight),
                      radius: Self.barHeight / 2, color: PaneCardStyle.trackColor)
        if let fraction = spec.remaining, fraction > 0 {
            let width = min(max(Self.barHeight, bounds.width * CGFloat(min(fraction, 1))), bounds.width)
            DrawnInk.fill(CGRect(x: 0, y: y, width: width, height: Self.barHeight),
                          radius: Self.barHeight / 2, color: Self.barColor(spec.remaining))
        }
        y += Self.barHeight + Self.spacing

        // 第三行：角标 + 窗口名 · 重置时间
        let text = Self.resetText(spec, compact: isCompact)
        if !text.isEmpty {
            let resetRun = DrawnTextRun(string: text, font: Self.resetFont,
                                        color: PaneCardStyle.tertiaryText)
            resetRun.draw(in: CGRect(x: 0, y: y, width: bounds.width, height: resetRun.lineHeight))
        }
    }

    // MARK: - 口径

    /// 重置行文案：会话 · 22:00 重置；有角标时前置「已限流 · 」
    ///
    /// 角标与重置时间并进一行而不是各占一行：总表格一行只有 34pt，
    /// 分两行会让三个窗口的表直接多出 33pt。
    static func resetText(_ spec: Spec, compact: Bool) -> String {
        var titleAndReset = spec.title
        // 窄列（三列约 52pt）只留窗口名：重置时间进 tooltip 与读屏文案，
        // 硬塞会把窗口名截成「5 小…」，而窗口名正是这一格的语义标签
        if !compact, let resetsAt = spec.resetsAt {
            // 不带「重置」二字：两列时每列约 98pt，「每周 · 11/25 05:58 重置」实测 100pt 会被截成
            // 「每周 · 11/25 05:5…」；原型 F1 的第二列同样只写「每周 · 11/23 08:00」
            let reset = BillingTimeFormat.reset(resetsAt, suffix: "")
            titleAndReset = titleAndReset.isEmpty ? reset : titleAndReset + " · " + reset
        }
        return titleAndReset
    }

    /// 角标不进这一行：状态胶囊已经表达「限流」，这里再写一遍会把
    /// 「周 · 11/25 05:34」这样的关键信息挤掉；角标改由 tooltip 与读屏文案承载。
    static func badgeText(_ spec: Spec) -> String? {
        guard let badge = spec.badge, !badge.isEmpty else { return nil }
        return badge
    }

    /// 数值色：与进度条同一套分级（低于 20% 危险、低于 50% 告警、其余正常）
    static func valueColor(_ remaining: Double?) -> NSColor {
        switch BillingCellLayout.level(for: remaining) {
        case .danger: return PaneCardStyle.requestInk
        case .warn: return PaneCardStyle.warnInk
        case .normal, .unavailable: return PaneCardStyle.primaryText
        }
    }

    /// 条色：与数值同一套分级
    static func barColor(_ remaining: Double?) -> NSColor {
        switch BillingCellLayout.level(for: remaining) {
        case .danger: return PaneCardStyle.requestColor
        case .warn: return PaneCardStyle.warnInk
        case .normal: return PaneCardStyle.okColor
        case .unavailable: return PaneCardStyle.ghostColor
        }
    }

    private static func accessibilityText(_ spec: Spec) -> String {
        let percent = formatPercent(spec.remaining)
        var reset = resetText(spec, compact: false)
        if let badge = badgeText(spec) {
            reset = reset.isEmpty ? badge : badge + " · " + reset
        }
        return reset.isEmpty ? spec.title + " 剩余 " + percent
                             : spec.title + " 剩余 " + percent + "，" + reset
    }
}
