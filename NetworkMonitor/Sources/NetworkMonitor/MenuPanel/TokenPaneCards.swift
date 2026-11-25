import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - Token 页卡片与图表基础件

/// 可点击卡片：圆角底 + 竖向内容栈（整卡可点，键盘焦点由面板根视图驱动）
///
/// 卡片一律是 MenuPanelRow 子类：悬停高亮 / 键盘焦点环 / Enter-空格触发三件
/// 都由基类提供，二级页入口和主面板区块共用同一套交互。
class TokenCardRow: MenuPanelRow {

    /// 内容容器（自上而下排列）
    let body = NSStackView()

    private let background: NSColor
    private let radius: CGFloat

    init(height: CGFloat,
         background: NSColor,
         radius: CGFloat = PaneCardStyle.cardRadius,
         paddingX: CGFloat = PaneCardStyle.cardPaddingX,
         paddingY: CGFloat = PaneCardStyle.cardPaddingY,
         spacing: CGFloat = PaneCardStyle.rowSpacing,
         onClick: (() -> Void)? = nil) {
        self.background = background
        self.radius = radius
        super.init(height: height, onClick: onClick)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = spacing
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        // 底部用 ≤ 而不是 ==：定高卡片的行数会随数据变化（0/1/3 行分布），
        // 底部约束只在「内容比卡片矮」时生效；内容高于卡片时变成可检测的
        // Auto Layout 冲突（而不是画到边界外、静默压住下一张卡）。
        // 同理也不再强制 ==：三行 distribution 恰好贴近 111pt，字号或文案一变就顶破。
        let bottom = body.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -paddingY)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
            body.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
            bottom,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }
}

/// 卡头：标题 + 弹簧 + 说明 + 可选右侧控件
final class TokenCardHead: NSView {

    private let titleLabel: NSTextField
    private let metaLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaNumberFont,
                                                color: TokenPaneStyle.tertiaryText)

    init(title: String, titleFont: NSFont = TokenPaneStyle.cardHeadTitleFont, trailing: NSView? = nil) {
        titleLabel = MenuPanelLabel.text(title, font: titleFont, color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, metaLabel, MenuPanelLabel.spacer()])
        if let trailing { stack.addArrangedSubview(trailing) }
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 13),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(title: String? = nil, meta: String) {
        if let title { titleLabel.stringValue = title }
        metaLabel.stringValue = meta
    }
}


/// 自适应高度卡片（二级页用）：底 + 内边距 + 竖向内容，高度由内容决定
final class TokenBoxView: NSView {

    let body = NSStackView()

    private let background: NSColor
    private let radius: CGFloat
    private let paddingX: CGFloat
    private let paddingY: CGFloat

    init(background: NSColor = PaneCardStyle.cardFill,
         radius: CGFloat = PaneCardStyle.cardRadius,
         paddingX: CGFloat = PaneCardStyle.boxPaddingX,
         paddingY: CGFloat = PaneCardStyle.boxPaddingY,
         spacing: CGFloat = 5) {
        self.background = background
        self.radius = radius
        self.paddingX = paddingX
        self.paddingY = paddingY
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = spacing
        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: paddingX),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -paddingX),
            body.topAnchor.constraint(equalTo: topAnchor, constant: paddingY),
            body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -paddingY),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        super.draw(dirtyRect)
    }

    /// 清空并重新装配行（二级页每次进入重建，避免残留旧数据）
    func setRows(_ rows: [NSView]) {
        for view in body.arrangedSubviews {
            body.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for row in rows { body.addArrangedSubview(row) }
        for row in rows where !(row is NSTextField) {
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
    }
}

/// 分族卡（2×2 首屏矩阵的一格）：标题行（含走势条）+ 大数值 + 一行辅助
///
/// r3 改版：走势条收进标题行右侧（不再单独占一行），同比与占比合并成一行辅助，
/// 卡片从「大数字 + 两行辅助」压成「大数字 + 一行辅助」，省下的高度全部给字号。
final class TokenFamilyCardView: TokenCardRow {

    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let unitLabel: NSTextField
    private let auxLabel: NSTextField
    private let spark = TokenSparkView(height: TokenPaneStyle.sparkHeight)
    private let miniBars = TokenMiniBarsView(height: TokenPaneStyle.sparkHeight)
    private var metricIndex = 0

    init(metric: TokenMetric, onClick: @escaping () -> Void) {
        titleLabel = MenuPanelLabel.text(metric.title, font: TokenPaneStyle.cardTitleFont,
                                         color: TokenPaneStyle.secondaryText)
        valueLabel = MenuPanelLabel.text("—", font: TokenPaneStyle.cardValueFont,
                                         color: TokenPaneStyle.secondaryText)
        unitLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaValueFont,
                                        color: TokenPaneStyle.tertiaryText)
        auxLabel = MenuPanelLabel.text("—", font: TokenPaneStyle.cardFooterFont,
                                       color: TokenPaneStyle.tertiaryText)
        metricIndex = metric.rawValue
        super.init(height: TokenPaneStyle.familyCardHeight,
                   background: TokenPaneStyle.metricCardFill(metric.rawValue),
                   spacing: 2,
                   onClick: onClick)

        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        auxLabel.lineBreakMode = .byTruncatingTail
        auxLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 走势条与标题同行：右端固定宽度，省掉卡片里的一整行
        let headRow = NSStackView(views: [titleLabel, MenuPanelLabel.spacer(), spark, miniBars])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        headRow.spacing = 4
        for chart in [spark as NSView, miniBars as NSView] {
            chart.widthAnchor.constraint(equalToConstant: TokenPaneStyle.cardSparkWidth).isActive = true
        }
        miniBars.isHidden = true

        let valueRow = NSStackView(views: [valueLabel, unitLabel])
        valueRow.orientation = .horizontal
        valueRow.alignment = .lastBaseline
        valueRow.spacing = 2
        unitLabel.setContentHuggingPriority(.required, for: .horizontal)

        for row in [headRow, valueRow, auxLabel] {
            body.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        setAccessibilityRole(.button)
        setAccessibilityLabel(metric.title + "详情")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(card: TokenFamilyCard) {
        titleLabel.stringValue = card.title
        valueLabel.stringValue = card.value
        valueLabel.textColor = TokenPaneStyle.metricInk(metricIndex)
        unitLabel.stringValue = card.unit
        auxLabel.stringValue = card.aux
        auxLabel.textColor = card.hasDelta
            ? (card.deltaUp ? TokenPaneStyle.warnInk : TokenPaneStyle.okInk)
            : TokenPaneStyle.tertiaryText

        let isBars = card.metric == .request
        spark.isHidden = isBars
        miniBars.isHidden = !isBars
        let accessibility = card.title + " " + card.value + " " + card.unit + " " + card.aux
        if isBars {
            miniBars.update(values: card.series, accessibility: accessibility)
        } else {
            spark.update(values: card.series, accessibility: accessibility)
        }
        setAccessibilityLabel(card.title + "详情，" + card.value + " " + card.unit)
        setAccessibilityValue(accessibility)
        // 悬停给该族口径（缓存读 / 未缓存 / 输出 / 请求数四者最容易混淆的是「请求数不进总量」）
        toolTip = TokenHoverTips.familyCardHint(metric: card.metric)
    }
}

/// 卡头小按钮：文字式（「14 天 ›」）与图标式（主图形态 / 指标切换）两种
///
/// 为什么主图那两个从「切：对比」「切：请求数」改成图标：用户反馈「下面的字很占空间」，
/// 而主图卡 meta 行宽度只有约 296pt。
/// 实测（NSButton.fittingSize，9.5pt chipFont）：「切：对比」42pt +「切：请求数」52pt
/// + 间距 6pt = **100pt**；改成 20pt 的 SF Symbol 后两个按钮 40pt + 间距 4pt = **44pt**，
/// 净省 **56pt**（56%），语义搬进 toolTip 与无障碍标签，一个字也没丢。
final class TokenTextButton: NSButton {

    var onClick: (() -> Void)?

    /// 图标模式下的固定宽度约束（切回文字模式要摘掉，否则「14 天 ›」会被压成 20pt）
    private var iconWidth: NSLayoutConstraint?

    init(title: String, toolTip: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
        font = TokenPaneStyle.textButtonFont
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = TokenPaneStyle.uncachedInk
        setButtonType(.momentaryChange)
        target = self
        action = #selector(handleClick)
        self.toolTip = toolTip
        setAccessibilityLabel(title)
    }

    /// 图标式初始化：只画一个 SF Symbol，语义由 toolTip + 无障碍标签承载
    ///
    /// - Parameter fallbackTitle: 系统取不到该符号时退回的短文字（不给就会变成一个空白按钮）
    convenience init(symbolName: String, fallbackTitle: String,
                     toolTip: String, accessibility: String) {
        self.init(title: fallbackTitle)
        update(symbolName: symbolName, fallbackTitle: fallbackTitle,
               toolTip: toolTip, accessibility: accessibility)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    @objc private func handleClick() { onClick?() }

    /// 图标态：title 清空、只留图（宽度固定 20pt，高度跟随行）
    ///
    /// 不说「切：」这两个字也不丢信息：toolTip 写清「当前什么、点击变成什么」，
    /// 读屏标签写同一句，键盘用户与鼠标用户拿到的是同一份说明。
    func update(symbolName: String, fallbackTitle: String,
                toolTip: String, accessibility: String) {
        let config = NSImage.SymbolConfiguration(pointSize: TokenPaneStyle.textButtonFont.pointSize,
                                                 weight: .semibold)
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        self.toolTip = toolTip
        setAccessibilityLabel(accessibility)
        guard let symbol else {
            // 符号不存在（更老的系统 / 拼错名字）：退回短文字，绝不留下一个看不见的空白按钮
            image = nil
            imagePosition = .noImage
            iconWidth?.isActive = false
            iconWidth = nil
            title = fallbackTitle
            return
        }
        title = ""
        image = symbol
        imagePosition = .imageOnly
        if iconWidth == nil {
            let width = widthAnchor.constraint(equalToConstant: 20)
            width.isActive = true
            iconWidth = width
        }
    }

    func update(title: String, toolTip: String? = nil) {
        // 切回文字模式：摘掉图标宽度约束、清图，否则文字被 20pt 硬宽裁掉
        iconWidth?.isActive = false
        iconWidth = nil
        image = nil
        imagePosition = .noImage
        self.title = title
        self.toolTip = toolTip
        setAccessibilityLabel(title)
    }
}