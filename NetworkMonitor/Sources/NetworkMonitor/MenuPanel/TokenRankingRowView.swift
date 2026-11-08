import AppKit
import NetworkMonitorCore

// MARK: - 排行屏的两行式分布行

/// 排行行：第一行 名称 + 右侧 tok / 占比；第二行 会话数 · 请求数；底一条行内微占比条
///
/// 为什么换掉改前的单行式：296pt 宽下单行只能塞下「名称 4.5 个字 + tok · 占比」，
/// 名称被截成「deepseek-v4.1-f…」、会话数无处可写；两行式让名称拿满一行。
/// 行高不写死：由排行屏按可见行数均分（4 行时行距舒展，8 行时收紧也不压行）。
@MainActor
final class TokenRankingRowView: NSView {

    private let swatch = TokenSwatch(color: TokenPaneStyle.ghostColor)
    private let nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowNameFont,
                                                color: TokenPaneStyle.secondaryText)
    private let amountLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowValueFont,
                                                  color: TokenPaneStyle.secondaryText)
    private let shareLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowPercentFont,
                                                 color: TokenPaneStyle.tertiaryText)
    private let metaLabel = MenuPanelLabel.text("", font: TokenPaneStyle.noteFont,
                                                color: TokenPaneStyle.tertiaryText)
    private let microBar = TokenStackBarView(height: 2)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.usesSingleLineMode = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        amountLabel.usesSingleLineMode = true
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        shareLabel.usesSingleLineMode = true
        shareLabel.setContentHuggingPriority(.required, for: .horizontal)
        metaLabel.usesSingleLineMode = true
        metaLabel.lineBreakMode = .byTruncatingTail

        let headRow = NSStackView(views: [swatch, nameLabel, MenuPanelLabel.spacer(),
                                          amountLabel, shareLabel])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 6

        let stack = NSStackView(views: [headRow, metaLabel, microBar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // 行高弹性：内容垂直居中，4 行与 8 行都不贴边
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            headRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            metaLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            microBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            // 8 行时也要放得下两行文字 + 微条
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// - Parameters:
    ///   - swatchColor: 行前色点（与占比条同一取色函数）
    ///   - showsProvider: 名称是否带 provider 前缀（排行屏不带：provider 在第二行）
    func update(row: TokenDistroRow, swatchColor: NSColor) {
        swatch.update(color: swatchColor)
        nameLabel.stringValue = row.name
        amountLabel.stringValue = row.amount
        shareLabel.stringValue = TokenFormatting.percent(row.share)
        metaLabel.stringValue = Self.metaText(row: row)
        microBar.update(shares: [row.share], colors: [swatchColor],
                        accessibility: row.name + " 占比 " + TokenFormatting.percent(row.share))
        // 悬停文案仍由 Core 拼装（同名模型的 provider / 命中率只在悬停里给全）
        let tip = row.tip.isEmpty ? nil : row.tip
        toolTip = tip
        nameLabel.toolTip = tip
        amountLabel.toolTip = tip
        metaLabel.toolTip = tip
        setAccessibilityLabel("第 " + String(row.rank) + " 名 " + row.name + " " + row.amount
            + " tok，占 " + TokenFormatting.percent(row.share) + "，" + metaLabel.stringValue)
    }

    /// 第二行：项目给「会话数 · 请求数」，模型给「provider · 请求数」
    private static func metaText(row: TokenDistroRow) -> String {
        let requests = TokenFormatting.grouped(row.requestCount) + " 次请求"
        if row.sessionCount > 0 {
            return String(row.sessionCount) + " 会话 · " + requests
        }
        let provider = row.provider.isEmpty ? "未记录 provider" : "provider " + row.provider
        return provider + " · " + requests
    }
}

#if DEBUG
extension TokenRankingRowView {

    /// 快照自证：当前挂上去的悬停文案
    var toolTipForSnapshot: String { toolTip ?? "" }

    /// 快照自证：名称 / 数值的可用与所需宽度（needed > available 即截断）+ 行高
    ///
    /// 与 TokenDistroRowView 的同名方法同形，排行屏台账与旧分布行台账可直接对比。
    func metricsForSnapshot(in reference: NSView)
        -> (available: CGFloat, needed: CGFloat, text: String, value: String,
            rowWidth: CGFloat, rowHeight: CGFloat, nameHeight: CGFloat,
            valueAvailable: CGFloat, valueNeeded: CGFloat) {
        layoutSubtreeIfNeeded()
        let nameFrame = nameLabel.convert(nameLabel.bounds, to: reference)
        let valueText = amountLabel.stringValue + " · " + shareLabel.stringValue
        return (snapshotTextArea(nameLabel),
                snapshotTextWidth(nameLabel.stringValue, font: nameLabel.font),
                nameLabel.stringValue,
                valueText,
                bounds.width,
                bounds.height,
                nameFrame.height,
                snapshotTextArea(amountLabel) + snapshotTextArea(shareLabel),
                snapshotTextWidth(valueText, font: amountLabel.font))
    }
}
#endif
