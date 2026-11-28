import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 设置页兼容层

/// `SettingsStyle` —— 兼容转发层
///
/// 令牌已搬到 `SettingsTheme`（取色 / 几何 / 字号唯一出口），这里保留同名成员做转发：
/// 二十多个设置页文件仍在用 `SettingsStyle.xxx`，调用点无需改动即可吃到新令牌。
/// **新代码一律直接用 `SettingsTheme`**，本层只为存量调用点存在。
@MainActor
enum SettingsStyle {
    /// 窗口初始尺寸（原型画布 760×540）
    static let windowSize = SettingsTheme.windowSize
    /// 侧栏宽度
    static let sidebarWidth = SettingsTheme.sidebarWidth
    /// 内容区左右内边距
    static let contentInset = SettingsTheme.contentInset
    /// 卡片圆角
    static let cardCornerRadius = SettingsTheme.cardRadius
    /// 卡片内单行最小高
    static let rowHeight = SettingsTheme.rowHeight
    /// 卡片内左右内边距（旧名保留：行的左右内边距与卡片内边距是同一档）
    static let rowInset = SettingsTheme.cardPaddingX

    /// 强调色
    static var accent: NSColor { SettingsTheme.accent }
    /// 页面底色（= 主题 `surface`）
    static var pageBackground: NSColor { SettingsTheme.surface }
    /// 卡片底色（= 主题 `cardFill`）
    static var cardBackground: NSColor { SettingsTheme.cardFill }
    /// 破坏性动作色（单一出口）
    static var destructive: NSColor { SettingsTheme.destructive }

    static let pageTitleFont = SettingsTheme.pageTitleFont
    static let sectionTitleFont = SettingsTheme.sectionTitleFont
    static let rowTitleFont = SettingsTheme.rowTitleFont
    static let rowValueFont = SettingsTheme.rowValueFont
    static let rowSubtitleFont = SettingsTheme.rowSubtitleFont
    static let noteFont = SettingsTheme.noteFont
}

// MARK: - 卡片

/// 设置卡片 — `cardFill` 实底 + 圆角 9 + 0.5pt 描边 + 顶部 1pt 高光
///
/// 与面板是同一卡形（不再是「白底 + 1pt 灰描边 + 圆角 10」这套旧语言）；
/// 行与行之间由 `addRow` 自动补 1pt 行分隔线（设置页每行是独立设置项，见 `SettingsDividerView`）。
final class SettingsCardView: NSView {

    private let rows = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        // 行栈四边钉死卡片：默认 gravityAreas 会把多余高度分到行与行之间
        rows.distribution = .fill
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        // 上下留卡片内边距，左右为 0 —— 行自己吃 10pt，行分隔线才不会顶到卡片边缘
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.cardPaddingY),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.cardPaddingY),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 卡片底直接 draw：离屏渲染换外观 / 换主题时动态语义色仍正确，圆角与描边也稳定可见
    override func draw(_ dirtyRect: NSRect) {
        SettingsTheme.drawCardBackground(in: bounds, hovered: isHovered)
    }

    // MARK: 悬停提亮

    /// 鼠标在卡片上：底色微亮一档，让「这一块是可以操作的」有可见反馈
    private var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// 清空全部行（整卡重建：重排时避免挪单行把自动补的分隔线搞乱；实例增删后同样走这里，
    /// 分隔线随 arrangedSubviews 一起移除）
    func removeAllRows() {
        for view in rows.arrangedSubviews {
            rows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    /// 追加一行延续行 —— 不补分隔线（它是上一行的下半部分，不是新的设置项）
    ///
    /// 用例：安装卡里「安装」行下方的进度区。它在 idle 态整块隐藏，
    /// 若照常补分隔线，隐藏后卡片里会留一条没人认领的横线。
    /// 单独开一个方法而不是给 addRow 加带默认值的参数：后者会让全仓
    /// 数组 forEach(卡片.addRow) 这类方法引用出现重载歧义（实测 32 条编译错误）。
    func addContinuationRow(_ row: NSView) {
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }

    /// 追加一行（自动在行间补分隔线）
    func addRow(_ row: NSView) {
        if !rows.arrangedSubviews.isEmpty {
            let divider = SettingsDividerView()
            rows.addArrangedSubview(divider)
            divider.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        rows.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }
}

// MARK: - 行

/// 通用设置行 — 左标题（可带副标题）+ 右控件
///
/// 右侧控件由调用方提供：开关、下拉、按钮、只读值（行值字体用 `SettingsTheme.rowValueFont`
/// 统一那一档等宽 11.5，控件自身字号仍由控件决定，保证读写逻辑零变化）。
/// 行最小高 32pt、左右内边距 10pt、上下 2pt，保证多行卡片横向严格对齐。
final class SettingsRowView: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowTitleFont,
                                                 color: SettingsTheme.textPrimary)
    private let subtitleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                    color: SettingsTheme.textTertiary)
    /// 行首小图标（按 SettingsRowIconMap 白名单取；未命中就不画，不留空位）
    private let iconView = NSImageView()
    /// 右侧控件容器（外部往里塞一个视图）
    let trailingStack = NSStackView()

    init(title: String, subtitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        // 副标题默认单行截断 + 悬停出全文气泡：设置页 11 页里绝大多数说明只有一句，
        // 全文铺开正是「密密麻麻全是字」的来源；需要两行的行（权限行）走 subtitleAllowsTwoLines()。
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.toolTip = subtitle

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = SettingsTheme.rowLabelSpacing

        // 行首图标：14pt 符号放在 16pt 宽的槽里，没配图标的行整槽隐藏，不占宽
        configureIcon(for: title)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let leading = NSStackView(views: [iconView, labels])
        leading.orientation = .horizontal
        leading.alignment = .centerY
        leading.spacing = 8

        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [leading, MenuPanelLabel.spacer(), trailingStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor,
                                         constant: SettingsTheme.cardPaddingX),
            row.trailingAnchor.constraint(equalTo: trailingAnchor,
                                          constant: -SettingsTheme.cardPaddingX),
            row.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.rowPaddingY),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.rowPaddingY),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsTheme.rowHeight),
        ])
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按 SettingsRowIconMap 的白名单给行配图标；没有对应符号时整槽隐藏（不留空位）
    private func configureIcon(for title: String) {
        guard let name = SettingsRowIconMap.symbol(for: title),
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            iconView.isHidden = true
            return
        }
        iconView.image = image
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iconView.contentTintColor = SettingsTheme.ghost
        iconView.isHidden = false
    }

    // MARK: 悬停高亮

    /// 指针在哪一行：整行淡淡提亮 —— 一屏十几行时「我现在看的是哪一项」要靠它
    private var isRowHovered = false {
        didSet { if isRowHovered != oldValue { needsDisplay = true } }
    }
    private var rowHoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowHoverTracking { removeTrackingArea(rowHoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        rowHoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) { isRowHovered = true }
    override func mouseExited(with event: NSEvent) { isRowHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard isRowHovered else { return }
        SettingsTheme.accent.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: SettingsTheme.cardPaddingX - 4, dy: 1),
                     xRadius: 5, yRadius: 5).fill()
    }

    /// 允许副标题折成两行（权限行的副标题要装「用途 + 处置办法」两句）
    ///
    /// 行高由内容撑开：默认单行在 760pt 窗口里会被截断成「重启 ...」，
    /// 而权限行的关键信息正是后半句。
    func subtitleAllowsTwoLines() {
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.toolTip = nil
    }

    /// 覆盖标题与副标题（状态变化时复用同一行）
    func update(title: String? = nil, subtitle: String?) {
        if let title {
            titleLabel.stringValue = title
            configureIcon(for: title)
        }
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.toolTip = subtitle
        if let title { setAccessibilityLabel(title) }
    }
}

// MARK: - 分隔线

/// 卡内行分隔线（1pt `rowSeparator` = `hairline`）
///
/// 与面板的**有意偏离**：面板卡内行是同一指标的多个读数，不画线才不碎；
/// 设置页每一行是独立设置项（开关 / 下拉 / 可编辑值），扫读靠横向对齐找行，
/// 所以相邻行之间画 1pt 线。线只画在卡片左右内边距以内、不触卡片边缘与圆角。
final class SettingsDividerView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let inset = SettingsTheme.cardPaddingX
        SettingsTheme.rowSeparator.setFill()
        NSRect(x: inset, y: bounds.minY,
               width: max(0, bounds.width - inset * 2), height: 1).fill()
    }
}

// MARK: - 动态背景面

/// 纯背景视图 — 背景色按当前外观 / 主题实时重算（离屏渲染换外观后仍是正确色）
///
/// 用途：设置窗口根视图、侧栏底、侧栏竖线。用静态 CGColor 会让深色快照出现浅色底，
/// 也会让换主题后的底色停在旧主题。
final class SettingsSurfaceView: NSView {

    private let colorProvider: () -> NSColor

    init(colorProvider: @escaping () -> NSColor) {
        self.colorProvider = colorProvider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = colorProvider().cgColor
    }
}

// MARK: - 翻转载体

/// 翻转坐标的容器 — 滚动视图的 documentView 必须是 flipped，否则内容从底部开始排，
/// 一屏放不下时看到的会是中间段（页头被顶出视口）。
final class SettingsFlippedView: NSView {
    override var isFlipped: Bool { true }
}