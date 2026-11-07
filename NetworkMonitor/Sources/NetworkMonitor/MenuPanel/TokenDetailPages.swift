import AppKit
import NetworkMonitorCore

// MARK: - Token 二级页（面板内覆盖式，不新开窗口）

/// 二级页种类
enum TokenDetailKind: Int, CaseIterable {
    case hourly
    case bucket
    case trend
    case cache
    case projects
    case models

    /// 返回条面包屑（bucket 页在运行时改写）
    var crumb: String {
        switch self {
        case .hourly: return "/ 按小时 · 三段拆分"
        case .bucket: return "/ 按小时"
        case .trend: return "/ 天趋势"
        case .cache: return "/ 缓存命中"
        case .projects: return "/ 按项目"
        case .models: return "/ 按模型"
        }
    }

    /// 返回条右侧说明 —— 「按项目 / 按模型」跟随主面板范围，文案取 Core 的 TokenDistroCopy
    ///
    /// 这里不再写死「累计口径」：这句话曾与主面板已跟随范围的「按项目 / 按模型」卡直接冲突，
    /// 用户看到上面是今日数据、下面写累计口径，反馈「上面的数据和下面的数据也对不上」。
    /// 视图只做透传，文案本身在 Core（TokenDerive.distroCopy）里派生，TestRunner 可直接断言。
    func metaText(for model: TokenPaneModel) -> String {
        switch self {
        case .hourly: return "00–23 时"
        case .bucket: return "单桶"
        case .trend: return "上限 33 天"
        // 缓存命中页跟随主面板范围：说明取当前范围（曾写死「今日」，与页面内容对不上）
        case .cache: return model.cachePage.crumbMeta
        case .projects: return model.distroCopy.projectsCrumbMeta
        case .models: return model.distroCopy.modelsCrumbMeta
        }
    }
}

/// 单桶选择（今日/昨日某小时，或窗口内某一天）
struct TokenBucketSelection {
    let index: Int
    let isHour: Bool
    let scope: TokenHourScope
}

/// 二级页容器：顶部「‹ Token」返回条 + 当前页内容
///
/// 覆盖在 Token 页内（同一 320pt 宽），进入隐藏首屏、返回恢复首屏；
/// 页面切换只重建内容栈，六页共用一套卡片样式（见两个扩展文件）。
@MainActor
final class TokenDetailPaneView: NSView {

    var onBack: (() -> Void)?
    /// 二级页内点柱：请求打开某个桶详情
    var onSelectBucket: ((TokenBucketSelection) -> Void)?

    private(set) var kind: TokenDetailKind = .hourly

    /// 二级页占满面板可视高度上限（与 MenuPanelView.desiredContentHeight 的外框同源）
    ///
    /// 页面内容高过它就变成纵向滚动，绝不裁切：520 − 顶 10 − 分段条 − 间距 12 − 底留白 12。
    static let paneMaxHeight: CGFloat = MenuPanelStyle.maxHeight - 10 - MenuTabBarView.barHeight
        - 12 - MenuPanelStyle.inset

    let backButton = TokenDetailBackButton()
    let crumbLabel = MenuPanelLabel.text(TokenDetailKind.hourly.crumb,
                                         font: TokenPaneStyle.pageHeadFont,
                                         color: TokenPaneStyle.tertiaryText)
    /// 右侧说明初值留空：真实文案在 update(kind:model:…) 里按当前范围填，
    /// 避免初始化时就写死一个可能过时的口径
    let metaLabel = MenuPanelLabel.text("",
                                        font: TokenPaneStyle.metaNumberFont,
                                        color: TokenPaneStyle.tertiaryText)
    /// 页内容栈（滚动文档里的排列容器）
    private let content = NSStackView()
    /// 页内容滚动区：返回条固定，内容区纵向滚动（样式与 MenuPanelView 内容区一致）
    private let scrollView = NSScrollView()
    /// 滚动文档（flipped，保证初始停在顶部）
    private let document = TokenDetailDocumentStack()
    /// 占位高度：显示时激活，让本页撑满面板可视高度上限；隐藏时停用，主面板高度照旧
    private var paneHeightConstraint: NSLayoutConstraint?

    /// 二级页的键盘焦点入口：只有返回按钮
    ///
    /// 二级页内容全是自绘卡片，没有可聚焦行；把返回按钮交给面板根视图的
    /// 焦点遍历，键盘用户才能 Tab 到「‹ Token」并回车返回。
    var focusableRows: [MenuPanelRow] { [backRow] }

    /// 返回按钮的行包装：复用面板行基类，从而继承焦点环、Enter/空格与读屏激活
    private lazy var backRow: MenuPanelRow = {
        let row = MenuPanelRow(height: 20) { [weak self] in self?.handleBack() }
        row.contentStack.addArrangedSubview(backButton)
        row.setAccessibilityLabel("返回 Token 主面板")
        return row
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("Token 二级详情页")

        backButton.target = self
        backButton.action = #selector(handleBack)
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)
        crumbLabel.lineBreakMode = .byTruncatingTail
        crumbLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // 返回按钮装进可聚焦行后整体放进返回条：一个视图只能有一个父视图，
        // 若同时挂在 bar 与 row 上，先加入 bar 的那个会被移走，返回条就空了
        let bar = NSStackView(views: [backRow, crumbLabel, MenuPanelLabel.spacer(), metaLabel])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 5
        bar.translatesAutoresizingMaskIntoConstraints = false

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false

        // 文档视图宽度跟随可视区（内容只做垂直滚动），高度由内容自然撑开
        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 0
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addArrangedSubview(content)
        content.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true
        // 底部留白 6pt：滚到底时最后一张卡不贴视口边
        let bottomPad = NSView()
        bottomPad.translatesAutoresizingMaskIntoConstraints = false
        bottomPad.heightAnchor.constraint(equalToConstant: 6).isActive = true
        document.addArrangedSubview(bottomPad)
        bottomPad.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bar)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // 覆盖在主面板之上：显示时按面板可视高度上限撑开，隐藏时让主面板按自身内容定高
        let height = heightAnchor.constraint(equalToConstant: Self.paneMaxHeight)
        height.isActive = false
        paneHeightConstraint = height
    }

    /// 显隐切换时同步占位高度约束（主面板与二级页各按自己的内容定高）
    override var isHidden: Bool {
        didSet {
            guard isHidden != oldValue else { return }
            paneHeightConstraint?.isActive = !isHidden
            if !isHidden { scrollToTop() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    @objc private func handleBack() { onBack?() }

    // MARK: - 装配

    func update(kind: TokenDetailKind,
                model: TokenPaneModel,
                snapshot: HarnessUsageSnapshot,
                selection: TokenBucketSelection?,
                hourScope: TokenHourScope) {
        self.kind = kind
        crumbLabel.stringValue = kind.crumb
        metaLabel.stringValue = kind.metaText(for: model)
        setAccessibilityLabel("Token 二级详情页 " + kind.crumb)
        let rows = buildRows(kind: kind, model: model, snapshot: snapshot,
                             selection: selection, hourScope: hourScope)
        clearContent()
        for row in rows {
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        // 换页后回到顶部，避免沿用上一页的滚动位置
        scrollToTop()
    }

    // MARK: - 滚动

    /// 回到顶部（换页 / 重新显示时调用）
    private func scrollToTop() {
        layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 内容是否高过可视区（DEBUG 取证与验收共用）
    var isContentScrollable: Bool {
        layoutSubtreeIfNeeded()
        return document.frame.height > scrollView.contentView.bounds.height + 0.5
    }

#if DEBUG
    /// 快照自证专用：返回（文档高度, 滚动视口高度）
    func snapshotScrollMetrics() -> (document: CGFloat, viewport: CGFloat) {
        layoutSubtreeIfNeeded()
        return (document.frame.height, scrollView.contentView.bounds.height)
    }

    /// 快照自证专用：压低视口高度，制造「内容高过视口」以证明滚动生效
    func setViewportHeightForSnapshot(_ height: CGFloat) {
        paneHeightConstraint?.constant = height
        layoutSubtreeIfNeeded()
    }

    /// 快照自证专用：滚到内容最底部
    func scrollToBottomForSnapshot() {
        layoutSubtreeIfNeeded()
        let maxY = max(0, document.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
#endif

    private func clearContent() {
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func buildRows(kind: TokenDetailKind,
                           model: TokenPaneModel,
                           snapshot: HarnessUsageSnapshot,
                           selection: TokenBucketSelection?,
                           hourScope: TokenHourScope) -> [NSView] {
        switch kind {
        case .hourly: return buildHourly(snapshot: snapshot, hourScope: hourScope)
        case .bucket: return buildBucket(model: model, snapshot: snapshot, selection: selection)
        case .trend: return buildTrend(snapshot: snapshot)
        case .cache: return buildCache(model: model)
        case .projects: return buildProjects(model: model)
        case .models: return buildModels(model: model)
        }
    }
}

/// 二级页滚动文档 — flipped，保证作为 NSScrollView.documentView 时初始停在顶部
private final class TokenDetailDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}
