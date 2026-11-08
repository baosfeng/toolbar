import AppKit
import NetworkMonitorCore

// MARK: - 概览屏「缓存命中」紧凑条

/// 概览屏的缓存命中条：小环 + 命中率大字 + 缓存读 / 未缓存 / 节省比例三值
///
/// 数据全部来自 Core 的 TokenCachePage（与缓存屏同一份派生，视图不重算比例）；
/// 整条可点 → 切到缓存屏看完整走势与对照（概览只给一行速览）。
@MainActor
final class TokenCacheHitStripView: TokenCardRow {

    private let ring = TokenRingView(size: 30, lineWidth: 3.4)
    private let hitValue = MenuPanelLabel.text("—", font: TokenPaneStyle.metaValueFont,
                                              color: TokenPaneStyle.cacheInk)
    private let hitUnit = MenuPanelLabel.text("%", font: TokenPaneStyle.cardValueUnitFont,
                                              color: TokenPaneStyle.tertiaryText)
    private let readCell = TokenMiniStatCell()
    private let uncachedCell = TokenMiniStatCell()
    private let savedCell = TokenMiniStatCell()

    init(onClick: (() -> Void)? = nil) {
        super.init(height: 42, background: TokenPaneStyle.cardFill, onClick: onClick)

        hitValue.setContentHuggingPriority(.required, for: .horizontal)
        let hitRow = NSStackView(views: [hitValue, hitUnit])
        hitRow.orientation = .horizontal
        hitRow.alignment = .lastBaseline
        hitRow.spacing = 1

        let row = NSStackView(views: [ring, hitRow, MenuPanelLabel.spacer(),
                                      readCell, uncachedCell, savedCell])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        body.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 只搬运 cachePage 的值（与缓存屏同一份派生）
    func update(page: TokenCachePage) {
        // 30pt 环里塞不下「97.3」（环心字体会溢出环），数字交给旁边的大字
        ring.update(rate: page.ringFraction, text: "", accessibility: page.ringAccessibility)
        hitValue.stringValue = page.ringText
        readCell.update(title: "缓存读", value: page.cacheReadText, color: TokenPaneStyle.cacheInk)
        uncachedCell.update(title: "未缓存", value: page.uncachedText)
        savedCell.update(title: page.saveRatioLabel, value: page.saveRatioText)
        setAccessibilityLabel("缓存命中率 " + page.ringText + "%，缓存读 " + page.cacheReadText
            + "，未缓存输入 " + page.uncachedText + "，" + page.saveRatioLabel + " "
            + page.saveRatioText + "。可切换到缓存屏")
    }
}

/// 紧凑条里的一格：8.5pt 标题 + 10pt 等宽数值
@MainActor
final class TokenMiniStatCell: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: TokenPaneStyle.axisFont,
                                                 color: TokenPaneStyle.tertiaryText)
    private let valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                                 color: TokenPaneStyle.secondaryText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.usesSingleLineMode = true
        valueLabel.usesSingleLineMode = true
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(title: String, value: String,
                color: NSColor = TokenPaneStyle.secondaryText) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        valueLabel.textColor = color
        setAccessibilityLabel(title + " " + value)
    }
}
