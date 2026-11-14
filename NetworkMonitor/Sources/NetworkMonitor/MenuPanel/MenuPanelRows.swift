import AppKit

// MARK: - 面板行（拆出自 MenuPanelComponents.swift，原文件超单文件 15 KiB 上限）

/// 面板行基类 — 悬停高亮、键盘聚焦环、Enter/空格触发点击
///
/// 键盘可达性由 `MenuPanelView` 统一驱动（见其 keyDown）：聚焦行由 `isKeyboardFocused`
/// 绘制高亮 + 焦点环，`activate()` 执行与鼠标点击相同的动作。
class MenuPanelRow: NSView {
    /// 点击回调；nil 表示纯展示行（不参与键盘焦点遍历）
    var onClick: (() -> Void)? {
        didSet { setAccessibilityRole(isInteractive ? .button : .group) }
    }

    /// 水平内容容器（子类向其中追加排列视图）
    let contentStack = NSStackView()

    /// 键盘聚焦态（由面板根视图设置）
    private(set) var isKeyboardFocused = false

    /// 悬停态（子类绘制悬停反馈时需要读；写入仍只在本类）
    private(set) var isHovered = false
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

    /// 角色必须随可点击性变化：面板里绝大多数可点元素都继承自本类
    /// （剪贴板条目、传送设备与任务、额度卡头、Token 卡片与「全部」表头），
    /// 原先只设了 label 没设 role，读屏能听到文案却按不动（VO-Space 无反应）。
    override func setAccessibilityLabel(_ accessibilityLabel: String?) {
        super.setAccessibilityLabel(accessibilityLabel)
        setAccessibilityRole(isInteractive ? .button : .group)
    }

    /// 读屏激活：与鼠标点击、键盘 Enter 走同一个 activate()
    override func accessibilityPerformPress() -> Bool {
        guard isInteractive else { return false }
        activate()
        return true
    }

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

    /// 按下：整行缩放到 0.96（设计文档 §7.2「按钮按下」）
    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return super.mouseDown(with: event) }
        TransferMotion.press(self)
    }

    override func mouseUp(with event: NSEvent) {
        guard isInteractive else { return super.mouseUp(with: event) }
        TransferMotion.release(self)
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
         valueColor: NSColor = .labelColor,
         titleColor: NSColor = MenuPanelStyle.secondaryText,
         onClick: (() -> Void)? = nil) {
        valueLabel = MenuPanelLabel.value(value, color: valueColor)
        super.init(height: MenuPanelStyle.rowHeight, onClick: onClick)

        if let symbol, let icon = MenuPanelLabel.symbol(symbol) {
            contentStack.addArrangedSubview(icon)
        }
        let titleLabel = MenuPanelLabel.text(title, font: MenuPanelStyle.bodyFont, color: titleColor)
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
    private let stateLabel = MenuPanelLabel.value("已关闭", color: MenuPanelStyle.secondaryText)

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
        trailingLabel = MenuPanelLabel.text(trailing, font: PaneCardStyle.metaFont,
                                            color: onClick == nil ? PaneCardStyle.tertiaryText : PaneCardStyle.secondaryText)
        super.init(height: onClick == nil ? PaneCardStyle.cardHeadHeight : 18, onClick: onClick)
        contentStack.addArrangedSubview(MenuPanelLabel.section(title))
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        trailingLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(trailingLabel)
    }

    func updateTrailing(_ text: String) {
        trailingLabel.stringValue = text
    }
}

/// 轻量卡片容器 — 五页统一的卡片面（今日流量 / 进程 / 图表 / 列表分组）
///
/// 底色与圆角**只从 `PaneCardStyle` 取**：此前这里是「半透明灰 + 8pt 圆角」，
/// 与额度 / Token / 系统页的「实色面 + 9pt 圆角」是两套公式，同面板切页时看得出两套质感。
/// 用 `draw` 阶段解析语义色，保证深浅色切换后即时跟随；
/// 若改用 layer.backgroundColor 会在创建瞬间固化 CGColor，切换外观后不刷新。
final class MenuPanelCardView: NSView {

    /// 卡内内容内边距 —— 与 `PaneCardBackgroundView` 共用同一组值
    static let contentInsetX: CGFloat = PaneCardStyle.cardPaddingX
    static let contentInsetY: CGFloat = PaneCardStyle.cardPaddingY

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 与 `PaneCardBackgroundView` 共用同一段玻璃三件套绘制：半透明底 + 顶部 1pt 高光 + 0.5pt 描边
        ThemeStyle.drawCard(in: bounds, radius: PaneCardStyle.cardRadius, fillRole: .cardFill)
        super.draw(dirtyRect)
    }

    /// 外观 / 主题变化后重绘
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 进度轨道（今日流量上下行占比）
final class MenuPanelTrackView: NSView {
    /// 填充比例 0...1
    var fraction: Double = 0 { didSet { needsDisplay = true } }
    /// 填充色（下行绿 / 上行橙）
    var fillColor: NSColor = MenuPanelStyle.downColor { didSet { needsDisplay = true } }

    /// - Parameter height: 轨道高度（默认 4pt；系统页卡头繁忙度微条用 3pt）
    init(fillColor: NSColor, height: CGFloat = 4) {
        self.fillColor = fillColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: height)])
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

// MARK: - 可点击卡片焦点协议

/// 可点击卡片的键盘焦点协议 — 给「整卡可点、但内部是多行布局」的卡片用
///
/// `MenuPanelRow` 固定单行布局，装不下系统页的五张多行卡片；这里只要求
/// 「能画焦点环 / 能执行点击」两件事，面板根视图把行与卡片合成一条焦序遍历
/// （行在前、卡片在后；系统页没有行，顺序即卡片自上而下）。
@MainActor
protocol MenuPanelCardFocusable: AnyObject {
    /// 当前是否持有键盘焦点（决定焦点环）
    var isCardKeyboardFocused: Bool { get }
    /// 设置键盘焦点
    func setCardKeyboardFocused(_ focused: Bool)
    /// 执行点击动作（鼠标与键盘共用）
    func activateCard()
}

// MARK: - 面板分页基类

/// 面板分页基类 — 三个 tab 的内容视图共同基类
///
/// `focusableRows` / `focusableCards` 给出该页内可点击元素的自上而下顺序，
/// 供面板根视图做键盘焦点遍历。
class MenuPanelPaneView: NSView {
    /// 键盘可达的行（自上而下）
    var focusableRows: [MenuPanelRow] { [] }
    /// 键盘可达的卡片（自上而下）— 默认无，系统页按需给
    var focusableCards: [any MenuPanelCardFocusable] { [] }
}

