import AppKit
import NetworkMonitorCore

// MARK: - 可折叠区块（手风琴）

/// 可折叠区块 —— 折叠时只留一行「高效信息」摘要，点击标题行展开详情
///
/// 交互约定（用户新增需求，原型没有）：
/// - 标题行整行可点，命中区 28pt；右侧 chevron 指示展开态（right → down）
/// - 展开 / 收起 0.2s easeInEaseOut，无弹跳
/// - 状态经 `KeyValueStorage` 持久化（不直读 UserDefaults），下次打开面板保持
/// - 摘要文字单行截断，320pt 宽度下不溢出
final class TokenCollapsibleSection: NSView {

    /// 展开态变化（供面板重算 popover 高度）
    var onToggle: (() -> Void)?

    /// 键盘可达的标题行
    let headerRow: MenuPanelRow = MenuPanelRow(height: TokenCollapsibleSection.rowHeight)
    /// 当前是否展开
    private(set) var isExpanded: Bool

    private static let rowHeight: CGFloat = 28
    private static let animationDuration: TimeInterval = 0.2

    private let titleLabel: NSTextField
    private let infoLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                               color: TokenPaneStyle.tertiaryText)
    private let chevronView = NSImageView()
    private let body = NSView()
    private let bodyContainer = NSView()
    private var bodyHeight: NSLayoutConstraint!
    /// 展开态内容高度（数据更新后重算）
    private var expandedHeight: CGFloat = 0
    private let storage: any KeyValueStorage
    private let storageKey: String

    // MARK: - 初始化

    /// - Parameters:
    ///   - title: 区块标题
    ///   - trailing: 标题行右侧控件（如图表形态切换，不参与折叠点击）
    ///   - content: 展开后显示的详情视图
    ///   - storage: 持久化存储（注入，测试可隔离）
    ///   - storageKey: 展开态存储键
    ///   - defaultExpanded: 首次使用的默认展开态
    init(title: String,
         trailing: NSView? = nil,
         content: NSView,
         storage: any KeyValueStorage,
         storageKey: String,
         defaultExpanded: Bool = false) {
        self.storage = storage
        self.storageKey = storageKey
        self.isExpanded = storage.bool(forKey: storageKey) || defaultExpanded
        self.titleLabel = MenuPanelLabel.text(title, font: TokenPaneStyle.sectionTitleFont,
                                             color: TokenPaneStyle.secondaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        configureHeader(trailing: trailing)
        configureBody(content: content)
        applyExpanded(isExpanded, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 外部接口

    /// 更新摘要（折叠态）与说明（展开态）
    func update(summary: String, expandedMeta: String) {
        infoLabel.stringValue = isExpanded ? expandedMeta : summary
        remeasureBody()
    }

    /// 切换展开态（点击 / 键盘触发）
    func toggle() {
        applyExpanded(!isExpanded, animated: true)
        storage.set(isExpanded, forKey: storageKey)
        onToggle?()
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：直接切换展开态，不写持久化
    func setExpandedForSnapshot(_ expanded: Bool) {
        applyExpanded(expanded, animated: false)
    }
#endif

    // MARK: - 装配

    private func configureHeader(trailing: NSView?) {
        headerRow.onClick = { [weak self] in self?.toggle() }
        headerRow.setAccessibilityLabel(titleLabel.stringValue + "，可展开或收起")
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // 摘要单行截断，保证 320pt 宽下不溢出
        infoLabel.lineBreakMode = .byTruncatingTail
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        infoLabel.alignment = .right

        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.contentTintColor = TokenPaneStyle.tertiaryText
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 10),
        ])

        headerRow.contentStack.spacing = 4
        headerRow.contentStack.addArrangedSubview(chevronView)
        headerRow.contentStack.addArrangedSubview(titleLabel)
        headerRow.contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        headerRow.contentStack.addArrangedSubview(infoLabel)
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerRow)
        NSLayoutConstraint.activate([
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerRow.topAnchor.constraint(equalTo: topAnchor),
        ])
        if let trailing {
            trailing.translatesAutoresizingMaskIntoConstraints = false
            addSubview(trailing)
            NSLayoutConstraint.activate([
                trailing.trailingAnchor.constraint(equalTo: trailingAnchor),
                trailing.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
                headerRow.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -6),
            ])
        } else {
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
    }

    private func configureBody(content: NSView) {
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.wantsLayer = true
        bodyContainer.layer?.masksToBounds = true
        addSubview(bodyContainer)

        content.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        body.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(body)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            content.topAnchor.constraint(equalTo: body.topAnchor),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            body.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            bodyContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 5),
            bodyContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bodyHeight = bodyContainer.heightAnchor.constraint(equalToConstant: 0)
        bodyHeight.isActive = true
    }

    // MARK: - 展开态

    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        chevronView.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                                    accessibilityDescription: expanded ? "收起" : "展开")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        bodyContainer.isHidden = !expanded
        body.alphaValue = expanded ? 1 : 0
        remeasureBody()
        guard animated else {
            bodyHeight.constant = expanded ? expandedHeight : 0
            bodyContainer.isHidden = !expanded
            return
        }
        let target = expanded ? expandedHeight : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            self.bodyHeight.constant = target
            self.body.alphaValue = expanded ? 1 : 0
            self.superview?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.bodyContainer.isHidden = !expanded
        })
    }

    /// 重算展开态内容高度（宽度由容器约束决定，按约束求最小高度）
    private func remeasureBody() {
        guard isExpanded else { return }
        bodyContainer.isHidden = false
        layoutSubtreeIfNeeded()
        expandedHeight = max(0, body.fittingSize.height)
        bodyHeight.constant = expandedHeight
    }
}