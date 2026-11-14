import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度页 Hero（最低剩余）

/// 首屏视觉重心：当前最紧急的额度窗口
///
/// 版式与 Token 页 Hero 同构（两行、固定高 `PaneCardStyle.heroHeight`）：
/// 第一行「最低剩余 · <provider> <窗口>」+ 右对齐实时时间；
/// 第二行主数值（24pt）+ 单位（11pt，分列）+ 右对齐重置时间。
/// 派生逻辑在 `BillingHeroLogic`（NetworkMonitorUI，可单测），本视图只负责排版。
final class BillingHeroView: NSView {

    private let titleLabel = MenuPanelLabel.text("最低剩余", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.secondaryText)
    private let valueLabel = MenuPanelLabel.text("—", font: PaneCardStyle.heroFont,
                                                 color: PaneCardStyle.primaryText)
    private let unitLabel = MenuPanelLabel.text("%", font: PaneCardStyle.heroUnitFont,
                                                color: PaneCardStyle.tertiaryText)
    private let clockLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 主数值与单位不可压缩：截断在这里等于丢失最重要的一条数据
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        unitLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        clockLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), clockLabel])
        headRow.orientation = .horizontal
        headRow.alignment = .firstBaseline
        headRow.spacing = 6

        let valueRow = NSStackView(views: [valueLabel, unitLabel, MenuPanelLabel.spacer()])
        valueRow.orientation = .horizontal
        valueRow.alignment = .lastBaseline
        valueRow.spacing = 2

        let stack = NSStackView(views: [headRow, valueRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PaneCardStyle.cardPaddingX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PaneCardStyle.cardPaddingX),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
            heightAnchor.constraint(equalToConstant: PaneCardStyle.heroHeight),
            headRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            valueRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.cardFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: PaneCardStyle.cardRadius,
                     yRadius: PaneCardStyle.cardRadius).fill()
        super.draw(dirtyRect)
    }

    /// 应用派生结果；nil 时主数值显示「—」而不是 0%
    ///
    /// - Parameters:
    ///   - hero: 最低剩余窗口（nil = 还没有可用数据）
    ///   - clock: 正常态且无数据时的时钟文案（如「尚未刷新」）
    ///   - isPaused: 是否因锁屏 / 休眠暂停了刷新；暂停时右侧一律显示暂停原因，
    ///     否则用户看到的是「一个不动的数字 + 一个不动的重置时间」，只会以为额度坏了。
    ///     重置时间并不丢：同屏的两格额度里各自写着「xx:xx 重置」。
    func update(hero: BillingHeroValue?, clock: String, isPaused: Bool = false) {
        if isPaused {
            if let hero {
                titleLabel.stringValue = hero.label
                applyPercent(hero.remaining)
                setAccessibilityLabel("\(hero.label) 剩余 \(valueLabel.stringValue)%（已暂停刷新）")
            } else {
                titleLabel.stringValue = "最低剩余"
                valueLabel.stringValue = "—"
                unitLabel.stringValue = "%"
                setAccessibilityLabel("已暂停刷新，暂无可用额度数据")
            }
            clockLabel.stringValue = BillingRefreshStatusLogic.clockText(isPaused: true, latestStamp: clock)
            clockLabel.textColor = PaneCardStyle.warnInk
            return
        }
        clockLabel.textColor = PaneCardStyle.tertiaryText
        if let hero {
            titleLabel.stringValue = hero.label
            applyPercent(hero.remaining)
            clockLabel.stringValue = Self.resetText(hero.resetsAt)
            setAccessibilityLabel("\(hero.label) 剩余 \(valueLabel.stringValue)%")
        } else {
            titleLabel.stringValue = "最低剩余"
            valueLabel.stringValue = "—"
            unitLabel.stringValue = "%"
            clockLabel.stringValue = clock
            setAccessibilityLabel("暂无可用额度数据")
        }
    }

    /// 剩余比例 → 「数值段 + 单位段」两段排版（大号数字走紧凑档，最多 2 位小数）
    ///
    /// 百分比也一律走分列：数值 24pt、单位 `%` 11pt，与 Token 页 `187.11` + `M tok` 同一语法。
    /// 用 `formatPercentCompact` 而不是 `formatPercent`：服务端会返回 `1 - 157/50000` 这种
    /// 六位小数（实测 `99.686%` / `49.058667%`），24pt 下会把半张卡撑满、逼另一列降档；
    /// 读屏与日志仍走 `formatPercent` 保留原值，只有这里的大号数字收紧凑。
    private func applyPercent(_ fraction: Double) {
        let split = PaneValueFormatting.split(formatPercentCompact(fraction))
        valueLabel.stringValue = split.number
        unitLabel.stringValue = split.unit.isEmpty ? "%" : split.unit
    }

    /// 重置时间：当天只给时分，跨天补日期；时分跟随系统 12/24 小时制
    static func resetText(_ date: Date?) -> String {
        guard let date else { return "无重置窗口" }
        return BillingTimeFormat.reset(date)
    }
}
