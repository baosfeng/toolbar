import AppKit

// MARK: - 剪贴板面板浮层（从 ClipboardPanelSupport 拆出，守住单文件体积上限）
//
// 首次引导态、快捷键帮助浮层与键帽视图：只做绘制与回调，键位数据与文案口径在
// ClipboardPanelSupport.swift，面板视图只负责挂载与显隐。

// MARK: - 键帽视图

/// 键帽 — 「⌘⇧⌫」这类按键文字胶囊，纯绘制、不参与交互
@MainActor
final class ClipboardKeyCapView: NSView {

    /// 键帽文字（唤起键会随偏好变化，故允许改写）
    var keyText: String {
        didSet {
            guard keyText != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            setAccessibilityLabel(keyText)
        }
    }

    /// 文本绘制属性（等宽字体；HUD 浮层传浅色，引导态跟随系统语义色）
    private let attributes: [NSAttributedString.Key: Any]
    /// 描边色
    private let strokeColor: NSColor

    init(text: String, textColor: NSColor = .labelColor, strokeColor: NSColor = .separatorColor) {
        self.keyText = text
        self.strokeColor = strokeColor
        self.attributes = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                           .foregroundColor: textColor]
        super.init(frame: .zero)
        // 自绘键帽：读屏按静态文本念「⌘⇧⌫」这类按键，而不是一个没有语义的绘图视图
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    override var isFlipped: Bool { true }

    /// 最小宽 34、高 20：短键（↵）不撑成方块，三连键（⌘⇧⌫）也不被裁切
    override var intrinsicContentSize: NSSize {
        let textSize = (keyText as NSString).size(withAttributes: attributes)
        return NSSize(width: max(34, ceil(textSize.width) + 16), height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        strokeColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()
        let textSize = (keyText as NSString).size(withAttributes: attributes)
        (keyText as NSString).draw(at: NSPoint(x: (bounds.width - textSize.width) / 2,
                                              y: (bounds.height - textSize.height) / 2),
                                   withAttributes: attributes)
    }
}

// MARK: - 首次引导态视图

/// 首次引导态 — 图标 + 两句话 + 三条快捷键胶囊 + 「知道了」
///
/// 只在面板首次打开且历史为空时由控制器显示；点「知道了」写偏好标记后不再出现。
@MainActor
final class ClipboardGuideView: NSView {

    /// 「知道了」被点击（由面板视图转交控制器写偏好）
    var onDismiss: (() -> Void)?

    /// 唤起键胶囊（文字随后按偏好刷新）
    private let toggleCapsule = ClipboardKeyCapView(text: ClipboardGuideText.toggleFallbackText)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    /// 刷新唤起键胶囊文字（键位可被用户改录制）
    func updateToggleHotKey(_ text: String) {
        toggleCapsule.keyText = text
    }

    private func build() {
        // 引导态整体作为一组：一句可读名概括它是什么（内部文案与按钮仍是各自独立的读屏元素）
        setAccessibilityRole(.group)
        setAccessibilityLabel("剪贴板首次使用引导：\(ClipboardGuideText.firstLine)。\(ClipboardGuideText.secondLine)")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: ClipboardGuideText.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.tertiaryLabelColor])))

        let lines = [ClipboardGuideText.firstLine, ClipboardGuideText.secondLine].map { text -> NSTextField in
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            return label
        }

        let capsules = NSStackView(views: [
            makeCapsule(toggleCapsule, action: ClipboardGuideText.toggleAction),
            makeCapsule(ClipboardKeyCapView(text: "↵"), action: "粘贴"),
            makeCapsule(ClipboardKeyCapView(text: "⌘1–9"), action: "直选"),
        ])
        capsules.orientation = .horizontal
        capsules.alignment = .centerY
        capsules.spacing = 16

        let dismiss = NSButton(title: ClipboardGuideText.dismissTitle, target: self, action: #selector(dismissTapped))
        dismiss.bezelStyle = .rounded
        dismiss.controlSize = .small
        // 读屏念「知道了，关闭引导」：只念「关闭引导」会让按钮标题与听到的内容对不上
        dismiss.setAccessibilityLabel("\(ClipboardGuideText.dismissTitle)，关闭引导")

        let stack = NSStackView(views: [icon] + lines + [capsules, dismiss])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
        ])
    }

    /// 键帽 + 作用文案横向组合
    private func makeCapsule(_ capsule: ClipboardKeyCapView, action: String) -> NSView {
        let label = NSTextField(labelWithString: action)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [capsule, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        // 键帽 + 作用合成一个读屏节点：分成两口念会听成「⌥⌘V」「唤起面板」两条互不相干的信息
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.staticText)
        stack.setAccessibilityLabel("\(capsule.keyText)，\(action)")
        capsule.setAccessibilityElement(false)
        label.setAccessibilityElement(false)
        return stack
    }

    @objc private func dismissTapped() { onDismiss?() }
}

// MARK: - 快捷键帮助浮层

/// 快捷键帮助浮层 — hudWindow 材质卡片 + 半透明遮罩，点外部或 Esc 收起，不抢焦点
///
/// 遮罩铺满面板内容区（含工具条与提示行），浮层卡片两列排布全部键位；
/// 面板是 .nonactivatingPanel，浮层自身不成为第一响应者，因此弹出时搜索框焦点不丢。
@MainActor
final class ClipboardShortcutHelpOverlay: NSView {

    /// 点遮罩（卡片之外）收起
    var onDismiss: (() -> Void)?

    private let card = NSVisualEffectView()
    /// 材质衬底：hudWindow 之上铺一层近不透明深色底（HUD 惯例），浅色外观下键位小字也可读
    private let cardFill = NSView()
    /// HUD 卡片底色（不随系统外观变化，与 macOS HUD 一致）
    private static let hudFill = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 0.94)
    /// HUD 主文字色
    private static let hudPrimary = NSColor.white.withAlphaComponent(0.92)
    /// HUD 次要文字色
    private static let hudSecondary = NSColor.white.withAlphaComponent(0.68)
    /// 卡片最大宽度（两列各 184 + 列间距 16 + 左右留白）
    private static let maxCardWidth: CGFloat = 420
    /// 卡片目标高度（标题 + 6 行键位）
    private static let cardHeight: CGFloat = 196
    /// 卡片与遮罩边缘的最小留白（面板最窄 420pt 时两列仍不压字）
    private static let cardInset: CGFloat = 10
    /// 单列宽度：键帽 60 + 间距 8 + 文案 116
    private static let columnWidth: CGFloat = 184
    /// 键帽列宽（保证两列键帽左对齐）
    private static let keycapWidth: CGFloat = 60
    /// 文案列宽（定宽避免两列互相压字）
    private static let actionWidth: CGFloat = 116

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    /// 遮罩：半透明黑，让底下的卡片流退后一档
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()
    }

    /// 整个遮罩接收鼠标：卡片内点击被吞下（不下发给底下卡片流、也不收起），卡片外点击收起
    ///
    /// 不返回 nil 是为了避免点击穿透到卡片流触发误粘贴；判断放在 mouseDown 里按位置做。
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard !card.frame.contains(local) else { return }
        onDismiss?()
    }


    private func build() {
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(card)

        let title = NSTextField(labelWithString: ClipboardShortcutHelp.title)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.textColor = Self.hudPrimary

        let stack = NSStackView(views: [title, makeGrid()])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        // 衬底插在材质与文案之间：材质边缘仍可见，字底稳定
        cardFill.wantsLayer = true
        cardFill.layer?.backgroundColor = Self.hudFill.cgColor
        card.addSubview(cardFill, positioned: .below, relativeTo: stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        ])
        setAccessibilityLabel(ClipboardShortcutHelp.title)
        // 收起路径对读屏要说得出口：Esc 或再点一次「快捷键帮助」按钮（浮层自身不设焦点）
        setAccessibilityHelp("按 Esc 或再次点按「快捷键帮助」收起")
    }

    override func layout() {
        super.layout()
        let width = min(Self.maxCardWidth, max(0, bounds.width - Self.cardInset * 2))
        let height = min(Self.cardHeight, max(0, bounds.height - Self.cardInset * 2))
        card.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                            width: width, height: height)
        cardFill.frame = card.bounds
    }

    /// 两列 × 6 行键位网格
    private func makeGrid() -> NSGridView {
        let entries = ClipboardShortcutHelp.entries
        let perColumn = (entries.count + 1) / 2
        var rows: [[NSView]] = []
        for row in 0..<perColumn {
            let left = makeEntryView(entries[row])
            let right = row + perColumn < entries.count ? makeEntryView(entries[row + perColumn]) : NSView()
            rows.append([left, right])
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 3
        return grid
    }

    /// 单条键位：定宽键帽（列内对齐）+ 作用文案
    private func makeEntryView(_ entry: ClipboardShortcutHelp.Entry) -> NSView {
        let keycap = ClipboardKeyCapView(text: entry.keys, textColor: Self.hudPrimary,
                                         strokeColor: NSColor.white.withAlphaComponent(0.22))
        keycap.setContentHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(labelWithString: entry.action)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Self.hudSecondary
        let stack = NSStackView(views: [keycap, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        label.lineBreakMode = .byTruncatingTail
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.staticText)
        stack.setAccessibilityLabel("\(entry.keys)，\(entry.action)")
        keycap.setAccessibilityElement(false)
        label.setAccessibilityElement(false)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.columnWidth).isActive = true
        keycap.widthAnchor.constraint(equalToConstant: Self.keycapWidth).isActive = true
        label.widthAnchor.constraint(equalToConstant: Self.actionWidth).isActive = true
        return stack
    }
}