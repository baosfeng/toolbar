import AppKit
import NetworkMonitorCore

// MARK: - 面板设计令牌

/// 菜单栏面板样式 — 颜色/字体/尺寸全部走系统语义 API（深浅色自适应）
///
/// 尺寸以 4pt 为基准；数字一律 `monospacedDigit`，避免每秒刷新时宽度抖动。
@MainActor
enum MenuPanelStyle {
    /// 面板宽度（设计稿 320）
    static let panelWidth: CGFloat = 320
    /// 内容左右留白
    static let inset: CGFloat = 12
    /// 面板最大高度（超出后内部区域滚动/截断，不无限长）
    static let maxHeight: CGFloat = 520
    /// 内容可用宽度
    static var contentWidth: CGFloat { panelWidth - inset * 2 }

    // MARK: 字体

    /// 分区标题
    static let sectionFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    /// 正文
    static let bodyFont = NSFont.systemFont(ofSize: 12)
    /// 数值（等宽数字）
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    /// 小号数值（进程行 / 图表数值）
    static let smallValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 主速率大数字
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
    /// 主速率单位
    static let heroUnitFont = NSFont.systemFont(ofSize: 11)
    /// 次速率数字
    static let sideValueFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)

    // MARK: 尺寸

    /// 普通行高
    static let rowHeight: CGFloat = 32
    /// 紧凑行高（进程行）
    static let compactRowHeight: CGFloat = 28
    /// 圆角
    static let cornerRadius: CGFloat = 8

    // MARK: 颜色

    static var downColor: NSColor { .systemGreen }
    static var upColor: NSColor { .systemOrange }
    static var accentColor: NSColor { .controlAccentColor }
    /// 轨道底色（labelColor 带透明度，深浅色自适应）
    static var trackColor: NSColor { NSColor.labelColor.withAlphaComponent(0.12) }
    /// 轻量填充（今日流量卡片 / 悬停行）
    static var subtleFill: NSColor { NSColor.labelColor.withAlphaComponent(0.06) }
    /// 图表柱（非今天）
    static var barColor: NSColor { NSColor.labelColor.withAlphaComponent(0.18) }
}

// MARK: - 标签工厂

/// 面板标签构造 — 统一字体/颜色/截断方式，避免各处手写 NSTextField 参数
@MainActor
enum MenuPanelLabel {

    /// 普通标签
    static func text(_ content: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: content)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    /// 分区标题（次要色 + 小号加粗）
    static func section(_ content: String) -> NSTextField {
        text(content, font: MenuPanelStyle.sectionFont, color: .secondaryLabelColor)
    }

    /// 弹性占位视图（NSStackView 中撑开两侧内容）
    static func spacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        return spacer
    }

    /// 数值标签（等宽数字）
    static func value(_ content: String, color: NSColor = .labelColor) -> NSTextField {
        text(content, font: MenuPanelStyle.valueFont, color: color)
    }

    /// SF Symbol 图标视图（模板色随语义色，禁止 emoji）
    static func symbol(_ name: String, pointSize: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> NSImageView? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let imageView = NSImageView()
        imageView.image = image.withSymbolConfiguration(config) ?? image
        imageView.contentTintColor = color
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: pointSize + 4),
            imageView.heightAnchor.constraint(equalToConstant: pointSize + 4),
        ])
        return imageView
    }
}

// MARK: - 面板行

/// 面板行基类 — 悬停高亮、键盘聚焦环、Enter/空格触发点击
///
/// 键盘可达性由 `MenuPanelView` 统一驱动（见其 keyDown）：聚焦行由 `isKeyboardFocused`
/// 绘制高亮 + 焦点环，`activate()` 执行与鼠标点击相同的动作。
class MenuPanelRow: NSView {
    /// 点击回调；nil 表示纯展示行（不参与键盘焦点遍历）
    var onClick: (() -> Void)?

    /// 水平内容容器（子类向其中追加排列视图）
    let contentStack = NSStackView()

    /// 键盘聚焦态（由面板根视图设置）
    private(set) var isKeyboardFocused = false

    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    init(height: CGFloat, onClick: (() -> Void)? = nil) {
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 是否可点击（决定是否进入键盘焦点遍历与显示手型光标）
    var isInteractive: Bool { onClick != nil }

    /// 设置键盘聚焦态
    func setKeyboardFocused(_ focused: Bool) {
        guard isKeyboardFocused != focused else { return }
        isKeyboardFocused = focused
        needsDisplay = true
    }

    /// 执行点击动作（鼠标与键盘共用）
    func activate() {
        onClick?()
    }

    override var acceptsFirstResponder: Bool { isInteractive }

    // MARK: 悬停

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        isHovered = true
        needsDisplay = true
        NSCursor.pointingHand.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        NSCursor.arrow.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive else { return super.mouseUp(with: event) }
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76:  // Return / Space / 小键盘 Enter
            activate()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        if isInteractive, isHovered || isKeyboardFocused {
            let rect = bounds.insetBy(dx: 0, dy: 1)
            let fill = isKeyboardFocused
                ? MenuPanelStyle.accentColor.withAlphaComponent(0.16)
                : MenuPanelStyle.subtleFill
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
        if isKeyboardFocused {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 6, yRadius: 6)
            ring.lineWidth = 2
            MenuPanelStyle.accentColor.setStroke()
            ring.stroke()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - 具体行

/// 键值行（左标题 + 右数值；`onClick` 非空时可点击）
final class MenuPanelKeyValueRow: MenuPanelRow {
    private let valueLabel: NSTextField

    init(symbol: String?, title: String, value: String,
         valueColor: NSColor = .labelColor, onClick: (() -> Void)? = nil) {
        valueLabel = MenuPanelLabel.value(value, color: valueColor)
        super.init(height: MenuPanelStyle.rowHeight, onClick: onClick)

        if let symbol, let icon = MenuPanelLabel.symbol(symbol) {
            contentStack.addArrangedSubview(icon)
        }
        let titleLabel = MenuPanelLabel.text(title, font: MenuPanelStyle.bodyFont, color: .secondaryLabelColor)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(valueLabel)
    }

    /// 更新右侧数值
    func updateValue(_ text: String, color: NSColor = .labelColor) {
        valueLabel.stringValue = text
        valueLabel.textColor = color
    }
}

/// 开关行（开机自启动）— 勾选图标 + 状态文案，整行可点击
final class MenuPanelToggleRow: MenuPanelRow {
    private let iconView = NSImageView()
    private let stateLabel = MenuPanelLabel.value("已关闭", color: .secondaryLabelColor)

    init(title: String, isOn: Bool, onToggle: @escaping () -> Void) {
        super.init(height: MenuPanelStyle.rowHeight, onClick: onToggle)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = MenuPanelStyle.accentColor
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
        ])
        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(MenuPanelLabel.text(title, font: MenuPanelStyle.bodyFont))
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        stateLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(stateLabel)
        update(isOn: isOn)
    }

    /// 更新开关态（勾选图标 + 文案）
    func update(isOn: Bool) {
        let symbol = isOn ? "checkmark" : "circle"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: isOn ? "已开启" : "已关闭")?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = isOn ? MenuPanelStyle.accentColor : .secondaryLabelColor
        stateLabel.stringValue = isOn ? "已开启" : "已关闭"
        stateLabel.textColor = isOn ? MenuPanelStyle.accentColor : .secondaryLabelColor
        setAccessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

/// 表头行（左侧分区标题 + 右侧补充说明）
final class MenuPanelHeaderRow: MenuPanelRow {
    private let trailingLabel: NSTextField

    init(title: String, trailing: String = "", onClick: (() -> Void)? = nil) {
        trailingLabel = MenuPanelLabel.text(trailing, font: MenuPanelStyle.smallValueFont,
                                            color: onClick == nil ? .tertiaryLabelColor : .secondaryLabelColor)
        trailingLabel.font = MenuPanelStyle.smallValueFont
        super.init(height: onClick == nil ? 16 : 20, onClick: onClick)
        contentStack.addArrangedSubview(MenuPanelLabel.section(title))
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(trailingLabel)
    }

    func updateTrailing(_ text: String) {
        trailingLabel.stringValue = text
    }
}

/// 轻量卡片容器 — 圆角填充块（今日流量等分组）
///
/// 用 `draw` 阶段解析语义色，保证深浅色切换后即时跟随；
/// 若改用 layer.backgroundColor 会在创建瞬间固化 CGColor，切换外观后不刷新。
final class MenuPanelCardView: NSView {

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        MenuPanelStyle.subtleFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: MenuPanelStyle.cornerRadius,
                     yRadius: MenuPanelStyle.cornerRadius).fill()
        super.draw(dirtyRect)
    }
}

/// 进度轨道（今日流量上下行占比）
final class MenuPanelTrackView: NSView {
    /// 填充比例 0...1
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    /// 填充色（下行绿 / 上行橙）
    var fillColor: NSColor = MenuPanelStyle.downColor { didSet { needsDisplay = true } }

    init(fillColor: NSColor) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 4)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        MenuPanelStyle.trackColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let width = bounds.width * max(0, min(1, fraction))
        guard width > 0 else { return }
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: width, height: bounds.height)
        fillColor.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()
    }
}

// MARK: - 面板分页基类

/// 面板分页基类 — 三个 tab 的内容视图共同基类
///
/// `focusableRows` 给出该页内可点击行的自上而下顺序，供面板根视图做键盘焦点遍历。
class MenuPanelPaneView: NSView {
    /// 键盘可达的行（自上而下）
    var focusableRows: [MenuPanelRow] { [] }
}
