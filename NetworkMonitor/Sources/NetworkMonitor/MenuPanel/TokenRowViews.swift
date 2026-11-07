import AppKit
import NetworkMonitorCore

// MARK: - Token 页行视图（分布行 / 对比行 / 键值行 / 图例 / 状态带）

/// 分布行：名称（尾部可省略）+「数值 · 占比」右对齐成一列
///
/// r3 改版：去掉左侧序号列（省 12–16pt 给名称）。半宽卡（主面板项目 / 模型）排两行——
/// 名称独占第一行拿满可用宽度，数值与占比右对齐成第二行；整宽列表（二级页）排单行，
/// 数值与占比固定在右侧一列。两种排法的行高都由 TokenPaneStyle 给死，块内统一。
final class TokenDistroRowView: NSView {

    private let nameLabel: NSTextField
    private let valueLabel: NSTextField

    init(height: CGFloat = TokenPaneStyle.distroRowHeight, stacked: Bool = true) {
        nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowNameFont,
                                        color: TokenPaneStyle.secondaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowValueFont,
                                         color: TokenPaneStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        // 单行强制：名称超长只走尾部省略，不允许回绕成两行（行高由 TokenPaneStyle 给死）
        nameLabel.usesSingleLineMode = true
        valueLabel.usesSingleLineMode = true
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: height),
        ])
        if stacked {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 0
            let detailRow = NSStackView(views: [MenuPanelLabel.spacer(), valueLabel])
            detailRow.orientation = .horizontal
            detailRow.alignment = .centerY
            detailRow.spacing = 0
            stack.addArrangedSubview(nameLabel)
            stack.addArrangedSubview(detailRow)
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            detailRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.addArrangedSubview(nameLabel)
            stack.addArrangedSubview(valueLabel)
            // 数值按自身文字宽度铺开（下限 distroValueWidth），名称拿剩下的宽度并尾部省略。
            // 原因：固定 44pt 时「3.37B · 20.4%」实测需要 75pt，每行数值都被截到「3.37B…」，
            // 而名称只用到 143pt、行内还空着 87pt。数值不截断、名称在空间不足时才截断。
            valueLabel.widthAnchor.constraint(
                greaterThanOrEqualToConstant: TokenPaneStyle.distroValueWidth).isActive = true
        }
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// - Parameter showsProvider: 半宽卡放不下 "provider/model"，主面板传 false（provider 在二级页与无障碍文案里保留）
    func update(row: TokenDistroRow, showsProvider: Bool = true) {
        let provider = (showsProvider && !row.provider.isEmpty) ? row.provider + "/" : ""
        nameLabel.stringValue = provider + row.name
        valueLabel.stringValue = row.amount + " · " + TokenFormatting.percent(row.share)
        // 悬停文案由 Core 拼装（row.tip）：半宽卡正文只放模型名时，同名模型的 provider 只能从悬停看到；
        // showsProvider=false 也必须设，否则主面板这两行仍是「一模一样且无处区分」。
        // 标签是子视图、会遮住整行的悬停命中区，所以三个视图都挂同一份文案，鼠标落在名字或数值上都能看到
        let tip = row.tip.isEmpty ? nil : row.tip
        toolTip = tip
        nameLabel.toolTip = tip
        valueLabel.toolTip = tip
        setAccessibilityLabel("\(row.rank) " + provider + row.name + " " + row.amount
            + " " + TokenFormatting.percent(row.share))
    }

#if DEBUG
    /// 快照自证：当前挂上去的悬停文案（复验「两行同名模型 tip 不同」）
    var toolTipForSnapshot: String { toolTip ?? "" }

    /// 快照自证：名称 / 数值标签的实到宽度与「完整显示所需宽度」（needed > available 即截断）
    ///
    /// 另给行宽 / 行高 / 名称实到高度：名称高过行高即「压行」，行宽用于复算可用宽度。
    func metricsForSnapshot(in reference: NSView)
        -> (available: CGFloat, needed: CGFloat, text: String, value: String,
            rowWidth: CGFloat, rowHeight: CGFloat, nameHeight: CGFloat,
            valueAvailable: CGFloat, valueNeeded: CGFloat) {
        layoutSubtreeIfNeeded()
        // 用「文字区宽度 vs 纯文本宽度」判定截断：NSTextField 的 cell 内边距会把
        // intrinsicContentSize 撑大 4pt，拿 frame 宽度直接比会漏判「刚好差 2pt」的省略。
        let nameFrame = nameLabel.convert(nameLabel.bounds, to: reference)
        return (snapshotTextArea(nameLabel),
                snapshotTextWidth(nameLabel.stringValue, font: nameLabel.font),
                nameLabel.stringValue,
                valueLabel.stringValue,
                bounds.width,
                bounds.height,
                nameFrame.height,
                snapshotTextArea(valueLabel),
                snapshotTextWidth(valueLabel.stringValue, font: valueLabel.font))
    }
#endif
}

/// 今日 vs 昨日对比行：名称 + 两条横条 + 数值
final class TokenCompareRowView: NSView {

    private let nameLabel: NSTextField
    private let valueLabel: NSTextField
    private let barView = TokenStackBarView(height: 6)
    private var fraction: Double = 0
    private var color: NSColor = TokenPaneStyle.ghostColor

    init() {
        nameLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowPercentFont,
                                        color: TokenPaneStyle.tertiaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.rowValueFont,
                                         color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        valueLabel.alignment = .right
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [nameLabel, barView, valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 14),
            nameLabel.widthAnchor.constraint(equalToConstant: 46),
            valueLabel.widthAnchor.constraint(equalToConstant: 54),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(name: String, text: String, fraction: Double, color: NSColor) {
        nameLabel.stringValue = name
        valueLabel.stringValue = text
        self.fraction = fraction
        self.color = color
        barView.update(shares: [fraction], colors: [color], accessibility: name + " " + text)
        setAccessibilityLabel(name + " " + text)
    }
}

/// 二级页键值行（左标签 + 右数值，可着色）
///
/// 两种排法，行高与字体都取自 TokenPaneStyle，不另立样式：
/// - 单行（默认）：标题按自身宽度定宽、数值吃掉剩余宽度并尾部省略；
/// - 堆叠（stacked）：标题独占第一行，数值整行铺开在第二行（字号降一级、颜色由调用点给），
///   用于「标题 + 长说明」都放不下的场景——单行放不下时不该让标题或数值任一方被切。
final class TokenKeyRowView: NSView {

    private let titleLabel: NSTextField
    private let valueLabel: NSTextField

    init(stacked: Bool = false) {
        titleLabel = MenuPanelLabel.text("", font: TokenPaneStyle.keyRowTitleFont,
                                         color: TokenPaneStyle.tertiaryText)
        valueLabel = MenuPanelLabel.text("", font: TokenPaneStyle.keyRowValueFont,
                                         color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 标题优先完整显示：标题按自身文字宽度定宽（不参与压缩），数值吃掉剩余宽度并尾部省略。
        // 反例（改前）：「按模型」页用超长 value（provider + 占比 + 命中率）时，
        // 值列挤压标题，标题只剩 "deeps…"；改用堆叠排法后两行各自完整。
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultHigh + 1, for: .horizontal)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.usesSingleLineMode = true
        valueLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if stacked {
            // 第二行是附属说明（provider + 占比 + 命中率），字号降一级，左对齐整行铺开
            valueLabel.font = TokenPaneStyle.noteFont
            valueLabel.alignment = .left
        } else {
            valueLabel.alignment = .right
        }

        let stack = NSStackView(views: [titleLabel, valueLabel])
        stack.orientation = stacked ? .vertical : .horizontal
        stack.alignment = stacked ? .leading : .firstBaseline
        stack.spacing = stacked ? 0 : 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if stacked {
            // 堆叠行沿用分布行的高（TokenPaneStyle.distroRowHeight），块内行高一致
            heightAnchor.constraint(equalToConstant: TokenPaneStyle.distroRowHeight).isActive = true
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            valueLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(title: String, value: String, color: NSColor = TokenPaneStyle.secondaryText) {
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        valueLabel.textColor = color
        setAccessibilityLabel(title + " " + value)
    }

#if DEBUG
    /// 快照自证：标题 / 数值的可用与所需宽度（needed > available 即截断）
    ///
    /// titleHeight > rowHeight 即标题被压行；rowWidth 用于复算可用宽度。
    func metricsForSnapshot(in reference: NSView)
        -> (title: String, titleAvailable: CGFloat, titleNeeded: CGFloat,
            value: String, valueAvailable: CGFloat, valueNeeded: CGFloat,
            rowWidth: CGFloat, rowHeight: CGFloat, titleHeight: CGFloat) {
        layoutSubtreeIfNeeded()
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: reference)
        return (titleLabel.stringValue,
                snapshotTextArea(titleLabel),
                snapshotTextWidth(titleLabel.stringValue, font: titleLabel.font),
                valueLabel.stringValue,
                snapshotTextArea(valueLabel),
                snapshotTextWidth(valueLabel.stringValue, font: valueLabel.font),
                bounds.width,
                bounds.height,
                titleFrame.height)
    }
#endif
}

#if DEBUG
/// 标签的可绘制文字宽度（去掉 cell 内边距）
fileprivate func snapshotTextArea(_ label: NSTextField) -> CGFloat {
    label.cell?.drawingRect(forBounds: label.bounds).width ?? label.bounds.width
}

/// 完整显示所需文字宽度（按当前字体量纯文本）
fileprivate func snapshotTextWidth(_ text: String, font: NSFont?) -> CGFloat {
    let size = (text as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 10.5)])
    return (size.width * 100).rounded(.up) / 100
}
#endif
