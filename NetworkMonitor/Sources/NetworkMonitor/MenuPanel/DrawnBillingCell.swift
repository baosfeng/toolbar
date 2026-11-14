import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度格（自绘）

/// 额度格 —— 「数值（19pt）+ 单位 + 名称 + 3pt 进度条 + 角标 / 重置时间」一次画完
///
/// **改造前**每格 7 个视图（数值 / 单位 / 名称 / 进度条 / 角标 / 重置 / 重置行容器）
/// 外加一个 NSStackView（4 行）+ 12 条约束；一个 provider 最多 3 格，
/// 一屏 3–6 个 provider 时光额度格就是 60–130 个视图。
///
/// 视觉令牌全部取 PaneCardStyle（19pt 数值 / 9.5pt 单位 / 10.5pt 名称 / 8.5pt 重置时间、
/// 3pt 条、行距 2pt），与改造前逐项同源；进度条最小填充宽 = 条高，与改造前一致。
@MainActor
final class DrawnBillingCell: NSView {


    /// 一格的全部绘制数据
    struct Spec: Equatable {
        /// 数值段（已拆出单位）
        var value: String
        /// 单位段（"%" 或金额单位；空 = 不画）
        var unit: String
        /// 名称（"5 小时" / "可用"）
        var title: String
        /// 剩余比例 0…1
        var fraction: Double
        /// 告警级别
        var level: BillingCellLayout.Level
        /// 角标（"已限流"；已按同行 / 分行规则处理）
        var badge: String?
        /// 重置时间文案（空 = 不画）
        var reset: String
        /// 是否画进度条（金额型余额没有百分比条）
        var showsBar: Bool
        /// 窄格：角标与重置时间分两行
        var compact: Bool
        /// 读屏文案
        var accessibility: String
    }

    /// 进度条高度（与改造前 BillingProgressBarView.preferredHeight 同值）
    static let barHeight: CGFloat = 3

    private(set) var spec: Spec? {
        didSet {
            guard spec != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            setAccessibilityLabel(spec?.accessibility)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.staticText)
    }

    /// 自上而下排版（与绘制里 y 递增的方向一致）
    override var isFlipped: Bool { true }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据更新

    /// 更新一格百分比限额
    func update(limit: BillingPercentLimit, compact: Bool = false) {
        let split = PaneValueFormatting.split(formatPercentCompact(limit.remainingFraction))
        let hasReset = limit.resetsAt != nil
        // 同行时角标带分隔符（"已限流 ·"），分行时原样
        let badge = BillingCellLayout.badgeText(limit.badge, hasReset: hasReset, compact: compact)
        spec = Spec(value: split.number,
                    unit: split.unit,
                    title: limit.title,
                    fraction: limit.remainingFraction,
                    level: BillingCellLayout.level(for: limit.remainingFraction),
                    badge: badge,
                    reset: Self.resetText(limit.resetsAt),
                    showsBar: true,
                    compact: compact,
                    accessibility: Self.accessibilityText(title: limit.title,
                                                          percent: formatPercent(limit.remainingFraction),
                                                          badge: limit.badge))
    }

    /// 金额型余额（provider 只给可用金额、没有百分比限额）
    func update(amount: String, title: String) {
        let split = PaneValueFormatting.split(amount)
        spec = Spec(value: split.number,
                    unit: split.unit,
                    title: title,
                    fraction: 0,
                    level: .normal,
                    badge: nil,
                    reset: "",
                    showsBar: false,
                    compact: false,
                    accessibility: title + " " + amount)
    }

    /// 恢复占位态
    func clear() {
        spec = Spec(value: "—",
                    unit: "",
                    title: "",
                    fraction: 0,
                    level: .normal,
                    badge: nil,
                    reset: "",
                    showsBar: true,
                    compact: false,
                    accessibility: "暂无额度数据")
    }

    // MARK: - 尺寸

    override var intrinsicContentSize: NSSize {
        guard let spec else { return NSSize(width: NSView.noIntrinsicMetric, height: 0) }
        return NSSize(width: NSView.noIntrinsicMetric, height: Self.contentHeight(for: spec))
    }

    /// 一格的内容总高（绘制与尺寸共用同一套口径）
    static func contentHeight(for spec: Spec) -> CGFloat {
        let spacing = PaneCardStyle.rowSpacing
        let valueRun = DrawnTextRun(string: spec.value, font: valueFont(for: spec.value),
                                    color: PaneCardStyle.primaryText)
        let titleRun = DrawnTextRun(string: spec.title, font: PaneCardStyle.rowNameFont,
                                    color: PaneCardStyle.tertiaryText)
        var height = valueRun.lineHeight + spacing + titleRun.lineHeight
        if spec.showsBar {
            height += spacing + barHeight
        }
        let footerLines = footerLineCount(for: spec)
        if footerLines > 0 {
            let lineHeight = DrawnTextRun(string: "0", font: PaneCardStyle.axisFont,
                                          color: PaneCardStyle.tertiaryText).lineHeight
            height += spacing + CGFloat(footerLines) * lineHeight
            if footerLines > 1 { height += compactLineSpacing }
        }
        return height
    }

    /// 数值字号档（长数值自动降一档，原值一个字符都不丢）
    static func valueFont(for number: String) -> NSFont {
        switch PaneValueSizing.tier(forNumber: number) {
        case .regular: return PaneCardStyle.cardValueFont
        case .compact: return PaneCardStyle.cardValueCompactFont
        case .dense:   return PaneCardStyle.cardValueDenseFont
        }
    }

    /// 角标行的行数（0 = 整行不画）
    static func footerLineCount(for spec: Spec) -> Int {
        BillingCellLayout.footerLineCount(hasBadge: !(spec.badge ?? "").isEmpty,
                                          hasReset: !spec.reset.isEmpty,
                                          compact: spec.compact)
    }

    /// 窄格两行之间的间距
    private static let compactLineSpacing: CGFloat = 1

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let spec, bounds.width > 0 else { return }
        let spacing = PaneCardStyle.rowSpacing
        let valueRun = DrawnTextRun(string: spec.value, font: Self.valueFont(for: spec.value),
                                    color: PaneCardStyle.primaryText)
        let unitRun = DrawnTextRun(string: spec.unit, font: PaneCardStyle.cardValueUnitFont,
                                   color: PaneCardStyle.tertiaryText)
        let titleRun = DrawnTextRun(string: spec.title, font: PaneCardStyle.rowNameFont,
                                    color: PaneCardStyle.tertiaryText)

        // 第一行：数值 + 单位（共用一条基线，视觉上读作「95 %」）
        var y: CGFloat = 0
        let unitWidth = spec.unit.isEmpty ? 0 : unitRun.width()
        let valueWidth = max(bounds.width - (spec.unit.isEmpty ? 0 : unitWidth + PaneValueFormatting.gap), 1)
        let baseline = y + valueRun.font.ascender
        valueRun.draw(baselineAt: baseline, x: 0, width: valueWidth)
        if !spec.unit.isEmpty {
            // 单位紧贴数值实测宽度（与改造前 2pt 间距一致），不是贴可用宽度的末尾
            let valueDrawnWidth = min(valueRun.width(), valueWidth)
            let unitX = min(valueDrawnWidth + PaneValueFormatting.gap, bounds.width)
            unitRun.draw(baselineAt: baseline, x: unitX, width: max(bounds.width - unitX, 1))
        }
        y += valueRun.lineHeight + spacing

        // 第二行：名称
        titleRun.draw(in: CGRect(x: 0, y: y, width: bounds.width, height: titleRun.lineHeight))
        y += titleRun.lineHeight + spacing

        // 第三行：进度条（最小填充宽 = 条高，与改造前一致）
        if spec.showsBar {
            drawBar(spec, at: y)
            y += Self.barHeight + spacing
        }

        drawFooter(spec, at: y)
    }

    private func drawBar(_ spec: Spec, at y: CGFloat) {
        let radius = max(Self.barHeight / 2, 1)
        DrawnInk.fill(CGRect(x: 0, y: y, width: bounds.width, height: Self.barHeight),
                      radius: radius,
                      color: PaneCardStyle.trackColor)
        guard spec.fraction > 0 else { return }
        let width = min(max(Self.barHeight, bounds.width * CGFloat(spec.fraction)), bounds.width)
        DrawnInk.fill(CGRect(x: 0, y: y, width: width, height: Self.barHeight),
                      radius: radius,
                      color: Self.fillColor(spec.level))
    }

    private func drawFooter(_ spec: Spec, at y: CGFloat) {
        let badgeRun = DrawnTextRun(string: spec.badge ?? "", font: PaneCardStyle.axisFont,
                                    color: PaneCardStyle.warnInk)
        let resetRun = DrawnTextRun(string: spec.reset, font: PaneCardStyle.axisFont,
                                    color: PaneCardStyle.tertiaryText)
        let badgeText = spec.badge ?? ""
        let lineHeight = badgeRun.lineHeight
        if spec.compact {
            var cursor = y
            if !badgeText.isEmpty {
                badgeRun.draw(in: CGRect(x: 0, y: cursor, width: bounds.width, height: lineHeight))
                cursor += lineHeight + Self.compactLineSpacing
            }
            if !spec.reset.isEmpty {
                resetRun.draw(in: CGRect(x: 0, y: cursor, width: bounds.width, height: lineHeight))
            }
            return
        }
        if !badgeText.isEmpty, !spec.reset.isEmpty {
            // 同行：共用一条基线，读作「已限流 · 2 小时 15 分」
            let baseline = y + badgeRun.font.ascender
            let badgeWidth = badgeRun.width()
            badgeRun.draw(baselineAt: baseline, x: 0, width: badgeWidth)
            let resetX = min(badgeWidth + 3, bounds.width)
            resetRun.draw(baselineAt: baseline, x: resetX, width: max(bounds.width - resetX, 1))
            return
        }
        let run = badgeText.isEmpty ? resetRun : badgeRun
        run.draw(in: CGRect(x: 0, y: y, width: bounds.width, height: lineHeight))
    }

    private static func fillColor(_ level: BillingCellLayout.Level) -> NSColor {
        switch level {
        case .normal: return PaneCardStyle.okColor
        case .warn:   return PaneCardStyle.warnInk
        case .danger: return PaneCardStyle.requestColor
        }
    }

    // MARK: - 口径

    /// 重置时间：当天只给时分，跨天补日期；时分跟随系统 12/24 小时制
    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        return BillingTimeFormat.reset(date)
    }

    private static func accessibilityText(title: String, percent: String, badge: String?) -> String {
        let base = title + " 剩余 " + percent
        guard let badge else { return base }
        return base + " " + badge
    }
}