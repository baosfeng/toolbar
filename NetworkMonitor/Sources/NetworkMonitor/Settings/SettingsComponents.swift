import AppKit

// MARK: - 设置页视觉常量

/// 设置窗口的尺寸与字体常量 — 与原型（application 风格）对齐
///
/// 只放常量与工厂，不放业务：页面各自组合组件，避免每个 pane 重复写字号与间距。
@MainActor
enum SettingsStyle {
    /// 窗口初始尺寸（原型画布）
    static let windowSize = NSSize(width: 760, height: 540)
    /// 侧栏宽度
    static let sidebarWidth: CGFloat = 168
    /// 内容区左右内边距
    static let contentInset: CGFloat = 24
    /// 卡片圆角
    static let cardCornerRadius: CGFloat = 10
    /// 卡片内单行高度（含上下内边距）
    static let rowHeight: CGFloat = 40
    /// 卡片内边距
    static let rowInset: CGFloat = 12

    static var accent: NSColor { MenuPanelStyle.accentColor }
    /// 页面底色（浅色下为浅灰）— 与白色卡片形成层次，纯白底会让卡片看不出边界
    static var pageBackground: NSColor { .underPageBackgroundColor }
    static var cardBackground: NSColor { .controlBackgroundColor }

    static let pageTitleFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    static let sectionTitleFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    static let rowTitleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let rowValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    static let rowSubtitleFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let noteFont = NSFont.systemFont(ofSize: 11, weight: .regular)
}

// MARK: - 页容器

/// 页容器 — 页头（标题 + 副标题）+ 若干卡片 + 底部说明，整体放进滚动视图
///
/// 用法：`let stack = SettingsPageStack(section: .providers)` → `stack.addCard(...)` → `stack.finish()`
/// （finish 必须在最后调用：它把底部说明与弹性空白补进去）。
final class SettingsPageStack: NSStackView {

    private let contentStack = NSStackView()

    init(section: SettingsSection) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = 0

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let title = MenuPanelLabel.text(section.title, font: SettingsStyle.pageTitleFont, color: .labelColor)
        let subtitle = MenuPanelLabel.text(section.subtitle, font: SettingsStyle.rowSubtitleFont,
                                           color: .secondaryLabelColor)
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4

        contentStack.addArrangedSubview(header)
        contentStack.setCustomSpacing(18, after: header)

        addArrangedSubview(contentStack)
        contentStack.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 追加一张卡片（可先加分组标题）
    func addCard(_ card: SettingsCardView, sectionTitle: String? = nil) {
        if let sectionTitle {
            let label = MenuPanelLabel.text(sectionTitle.uppercased(),
                                            font: SettingsStyle.sectionTitleFont,
                                            color: .secondaryLabelColor)
            contentStack.addArrangedSubview(label)
            contentStack.setCustomSpacing(6, after: label)
        }
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(16, after: card)
    }

    /// 页尾说明（灰色小字）
    func addNote(_ text: String) {
        let note = MenuPanelLabel.text(text, font: SettingsStyle.noteFont, color: .tertiaryLabelColor)
        note.maximumNumberOfLines = 3
        note.lineBreakMode = .byWordWrapping
        contentStack.addArrangedSubview(note)
    }
}

// MARK: - 卡片

/// 设置卡片 — 圆角背景 + 1pt 边框，内部按行垂直排布（行之间自动补分隔线）
final class SettingsCardView: NSView {

    private let rows = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 卡片底直接 draw：离屏渲染换外观时动态语义色仍正确，圆角与描边也稳定可见
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: SettingsStyle.cardCornerRadius,
                                yRadius: SettingsStyle.cardCornerRadius)
        SettingsStyle.cardBackground.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
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
/// 右控件由调用方提供：开关、下拉、按钮、只读值。行高固定 40pt，保证多行卡片对齐。
final class SettingsRowView: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: SettingsStyle.rowTitleFont, color: .labelColor)
    private let subtitleLabel = MenuPanelLabel.text("", font: SettingsStyle.rowSubtitleFont,
                                                   color: .secondaryLabelColor)
    /// 右侧控件容器（外部往里塞一个视图）
    let trailingStack = NSStackView()

    init(title: String, subtitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [labels, MenuPanelLabel.spacer(), trailingStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsStyle.rowInset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsStyle.rowInset),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsStyle.rowHeight),
        ])
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 覆盖标题与副标题（状态变化时复用同一行）
    func update(title: String? = nil, subtitle: String?) {
        if let title { titleLabel.stringValue = title }
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        if let title { setAccessibilityLabel(title) }
    }
}

// MARK: - 分隔线

/// 卡片内行分隔线（1pt，跟随语义色）
final class SettingsDividerView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
    }
}
// MARK: - 动态背景面

/// 纯背景视图 — 背景色按当前外观实时重算（离屏渲染换外观后仍是正确色）
///
/// 用途：设置窗口根视图与侧栏底色。用静态 CGColor 会让深色快照出现浅色底。
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
