import AppKit

// MARK: - 二级详情页共用组件

/// 详情页卡片壳 — 语义 wash 底 + 可选卡头（标题 / 附属件 / 右侧口径）+ 垂直内容区
///
/// 与首屏 `SystemCardView` 分开：详情页卡头没有「›」入口、没有整卡点击，
/// 但多了带单位的右侧口径文案（「用户 / 系统」「wired → active → compressed」）。
final class SystemDetailCardView: NSView {

    private let contentStack = NSStackView()
    private let metaLabel: NSTextField
    private let headerAccessorySlot = NSStackView()
    private let washColor: NSColor

    init(title: String = "", meta: String = "", wash: NSColor, accessory: NSView? = nil) {
        washColor = wash
        metaLabel = MenuPanelLabel.text(meta,
                                        font: SystemPaneStyle.microFont,
                                        color: SystemPalette.meta)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        outer.translatesAutoresizingMaskIntoConstraints = false

        if !title.isEmpty {
            headerAccessorySlot.orientation = .horizontal
            headerAccessorySlot.alignment = .centerY
            headerAccessorySlot.spacing = 4
            if let accessory {
                headerAccessorySlot.addArrangedSubview(accessory)
            }
            let titleLabel = MenuPanelLabel.text(title,
                                                 font: MenuPanelStyle.sectionFont,
                                                 color: SystemPalette.foregroundSecondary)
            let header = NSStackView(views: [titleLabel, headerAccessorySlot,
                                             MenuPanelLabel.spacer(), metaLabel])
            header.orientation = .horizontal
            header.alignment = .centerY
            header.spacing = 5
            outer.addArrangedSubview(header)
            header.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        }
        outer.addArrangedSubview(contentStack)
        contentStack.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true

        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.isEmpty ? "详情卡片" : title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        washColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        super.draw(dirtyRect)
    }

    /// 追加一行内容（自动撑满卡片内容宽）
    func addContent(_ view: NSView) {
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    /// 更新右侧口径文案
    func updateMeta(_ text: String) {
        metaLabel.stringValue = text
    }
}

// MARK: - 返回键

/// 「‹ 系统」返回键 — 无边框按钮 + 自绘 soft-fill 药丸底（layer 背景会固化 CGColor）
final class SystemDetailBackButton: NSButton {

    private static let buttonFont = NSFont.systemFont(ofSize: 10, weight: .bold)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        title = "系统"
        font = Self.buttonFont
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = SystemPalette.foreground
        if let image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            self.image = image.withSymbolConfiguration(config) ?? image
            imagePosition = .imageLeading
        }
        setButtonType(.momentaryChange)
        setAccessibilityLabel("返回系统页")
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        SystemPalette.softFill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        super.draw(dirtyRect)
    }
}

// MARK: - 压力徽标

/// 内存压力徽标 — 药丸底 + ink 文字 + 1pt 内描边（正常 / 警示 / 严重 / 未知）
final class SystemPressureBadgeView: NSView {

    private let label: NSTextField
    private var level: SystemPressureDotView.Level = .unknown

    init() {
        label = MenuPanelLabel.text("—", font: NSFont.systemFont(ofSize: 9, weight: .bold),
                                    color: SystemPalette.memoryInk)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = false
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 15),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新压力等级（未知显示「—」并转灰）
    func update(_ level: SystemPressureDotView.Level) {
        self.level = level
        switch level {
        case .normal:
            label.stringValue = "正常"
            label.textColor = SystemPalette.memoryInk
        case .warning:
            label.stringValue = "警示"
            label.textColor = SystemPalette.warnInk
        case .critical:
            label.stringValue = "严重"
            label.textColor = SystemPalette.dangerInk
        case .unknown:
            label.stringValue = SystemPaneFormat.placeholder
            label.textColor = SystemPalette.meta
        }
        setAccessibilityLabel("内存压力 \(label.stringValue)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background: NSColor
        let border: NSColor?
        switch level {
        case .normal:
            background = SystemPalette.color(.cardMemory)
            border = SystemPalette.memoryCompressed
        case .warning:
            background = SystemPalette.color(.cardMemory)
            border = SystemPalette.warn
        case .critical:
            background = SystemPalette.color(.cardMemory)
            border = SystemPalette.danger
        case .unknown:
            background = SystemPalette.color(.cardMemory)
            border = nil
        }
        let radius = max(1, bounds.height / 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)
        background.setFill()
        path.fill()
        if let border {
            path.lineWidth = 1
            border.setStroke()
            path.stroke()
        }
    }
}

// MARK: - 多行说明

/// 详情页脚注 — 8.5pt 弱文字、自动换行（首屏 toolTip 才是长口径的归属）
final class SystemDetailNoteView: NSView {

    private let label: NSTextField

    init(_ text: String = "") {
        label = NSTextField(wrappingLabelWithString: text)
        label.font = SystemPaneStyle.tinyFont
        label.textColor = SystemPalette.meta
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新文案
    func update(_ text: String) {
        label.stringValue = text
    }
}
