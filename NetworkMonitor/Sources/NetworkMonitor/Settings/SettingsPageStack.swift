import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 页容器

/// 页容器 — 页头（标题 + 说明 + 可选状态胶囊）+ 分组标题 + 若干卡片 + 页尾说明
///
/// 用法：`let stack = SettingsPageStack(section: .providers)` → `addCard(...)` →
/// 需要时 `setStatusChip(...)`。内容整体放进滚动视图，页尾由弹性空白吸底。
///
/// 间距规则（与定稿一致，不再是「一律 8pt」）：
/// 页头 → 首个分组/卡片 12、分组标题 → 卡片 6、卡片 → 卡片 10、卡片/分组 → 分组标题 12、
/// 卡片 → 页尾说明 10、说明 → 说明 4。
final class SettingsPageStack: NSStackView {

    private let contentStack = NSStackView()
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private let statusChipView = SettingsStatusChipView()
    /// 上一个加进内容栈的元素类别（决定下一段间距）
    private enum ElementKind { case header, group, card, note }
    private var lastView: NSView?
    private var lastKind: ElementKind = .header
    /// 可折叠分组（按出现顺序；点组头的箭头折叠本组卡片）
    private var groups: [GroupState] = []
    /// 当前分组：没有分组标题的卡片归到它
    private var currentGroup: GroupState?

    init(section: SettingsSection) {
        titleLabel = MenuPanelLabel.text(section.title, font: SettingsTheme.pageTitleFont,
                                        color: SettingsTheme.textPrimary)
        subtitleLabel = MenuPanelLabel.text(section.subtitle, font: SettingsTheme.pageSubtitleFont,
                                            color: SettingsTheme.textSecondary)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = 0
        // 必须显式 .fill：NSStackView 默认是 .gravityAreas，容器比内容高时
        // 剩余空间会被均分到 gravity 区之间 —— 表现就是「标题在顶、卡片在底、
        // 中间一大片空白」。首次打开设置页时容器高度先按视口撑满，
        // 正好命中这个条件；第二次进入高度已被算准，所以「再进一次就好了」。
        distribution = .fill

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.distribution = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        // 标题必读：压缩时优先压胶囊 / 占位，不压标题
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping

        // 标题行：图标徽章 + 标题 + 状态胶囊（胶囊属于标题而不是右侧操作）
        // 图标让每页开场就有一个「这是什么功能」的视觉锚点，而不是一整片文字
        let iconBadge = SettingsPageIconView(symbolName: section.symbolName)
        let titleRow = NSStackView(views: [iconBadge, titleLabel, statusChipView, MenuPanelLabel.spacer()])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 9
        titleRow.setCustomSpacing(SettingsTheme.statusChipSpacing, after: titleLabel)
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [titleRow, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 4
        header.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(contentStack)
        contentStack.widthAnchor.constraint(equalTo: widthAnchor).isActive = true

        append(header, gapBefore: 0, kind: .header)
        titleRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        // 弹性尾部空白：把多余高度全部吸到最底部，内容始终贴顶
        let tail = NSView()
        tail.translatesAutoresizingMaskIntoConstraints = false
        tail.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        tail.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        addArrangedSubview(tail)
        tail.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: 外观

    /// 挂 / 换 / 取下页头状态胶囊（nil = 不显示）
    ///
    /// 各页在 `refresh()` 里按真实状态调用；没有真实状态的页不要挂空胶囊。
    func setStatusChip(_ chip: SettingsStatusChip?) {
        statusChipView.update(chip)
    }

    // MARK: 内容

    /// 追加一张卡片（可先加分组标题）
    ///
    /// - Parameter trailingAccessory: 放在分组标题行右侧的附加控件（如可排序卡片的「恢复默认」按钮）；
    ///   标题行会与之左右分栏，卡片本身宽度仍与内容栈对齐。
    func addCard(_ card: SettingsCardView,
                 sectionTitle: String? = nil,
                 trailingAccessory: NSView? = nil) {
        if let sectionTitle {
            let header = SettingsGroupHeaderView(title: sectionTitle, trailingAccessory: trailingAccessory)
            let group = GroupState(header: header)
            header.onToggle = { [weak self] in self?.toggle(group) }
            groups.append(group)
            currentGroup = group
            append(header, gapBefore: SettingsTheme.groupSpacingTop, kind: .group)
            append(card, gapBefore: SettingsTheme.groupSpacingBottom, kind: .card)
            group.cards.append(card)
        } else {
            let gap = lastKind == .header ? SettingsTheme.groupSpacingTop : SettingsTheme.cardSpacing
            append(card, gapBefore: gap, kind: .card)
            // 没有分组标题的卡片归到上一个分组，点组头时一起收起
            currentGroup?.cards.append(card)
        }
    }

    /// 一个可折叠分组：标题行 + 它的卡片（折叠时一起收，展开时逐张淡入）
    private final class GroupState {
        let header: SettingsGroupHeaderView
        var cards: [SettingsCardView] = []
        var isCollapsed = false
        init(header: SettingsGroupHeaderView) { self.header = header }
    }

    /// 折叠 / 展开一个分组
    ///
    /// 动效口径：收起 0.12s 淡出后落 isHidden（高度跳变发生在看不见的时候），
    /// 展开逐张淡入 + 上移 6pt（MotionKit.stagger 错峰）—— 与切页入场同一套语言。
    private func toggle(_ group: GroupState) {
        group.isCollapsed.toggle()
        group.header.setCollapsed(group.isCollapsed)
        if group.isCollapsed {
            for card in group.cards {
                MotionKit.fadeOut(card, duration: MotionKit.durations.close) { card.isHidden = true }
            }
        } else {
            for (index, card) in group.cards.enumerated() {
                card.isHidden = false
                card.alphaValue = 0
                MotionKit.fadeIn(card, offsetY: 6, delay: MotionKit.stagger(index: index))
            }
        }
    }

    /// 追加自定义控件（按下文元素的间距规则与上一个元素隔开）
    ///
    /// 用途：内容要在状态变化后整块重写的元素（如权限页的提示块）不能走 `addNote`。
    func addRow(_ view: NSView, gapBefore: CGFloat? = nil) {
        let gap: CGFloat
        if let gapBefore {
            gap = gapBefore
        } else {
            switch lastKind {
            case .header: gap = SettingsTheme.groupSpacingTop
            case .note:   gap = SettingsTheme.noteGap
            default:      gap = SettingsTheme.noteSpacing
            }
        }
        append(view, gapBefore: gap, kind: .note)
    }

    /// 页尾说明（三级色小字）
    func addNote(_ text: String) {
        let note = MenuPanelLabel.text(text, font: SettingsTheme.noteFont,
                                       color: SettingsTheme.textTertiary)
        note.maximumNumberOfLines = 3
        note.lineBreakMode = .byWordWrapping
        let gap: CGFloat
        switch lastKind {
        case .header: gap = SettingsTheme.groupSpacingTop
        case .note:   gap = SettingsTheme.noteGap
        default:      gap = SettingsTheme.noteSpacing
        }
        append(note, gapBefore: gap, kind: .note)
    }

    // MARK: 入场动效

    /// 切页入场：卡片逐张淡入 + 上移，按 MotionKit 的错峰口径排开
    ///
    /// 整页一次性淡入体感不够「这是新的一页」；卡片按顺序出现，视线自然从上往下带，
    /// 一屏十几行也不会糊成一片。系统「减弱动态效果」或省电档时 MotionKit 直接落终态。
    func animateEntrance() {
        for (index, view) in contentStack.arrangedSubviews.enumerated() {
            MotionKit.fadeIn(view, offsetY: 8, delay: MotionKit.stagger(index: index))
        }
    }

    // MARK: 滚动定位

    /// 把内容里的某个视图滚进可视区
    ///
    /// 为什么需要：关于页内容实测约 880pt、可视 540pt，安装卡在页面最底部——
    /// 用户点「下载并安装」时进度区落在视口外，等于「加了进度但看不见」。
    ///
    /// 坐标口径：滚动的是本视图所在的 NSScrollView，传进 `scrollToVisible` 的矩形必须
    /// 是 **clipView 坐标系**（它的原点随滚动移动），所以先 convert 到 contentView。
    /// 先 `layoutSubtreeIfNeeded()` 是必须的：进度区从 0 高切到 52pt 的同一跑里
    /// 约束还没算完，此刻 convert 出来的是旧几何，会滚到错的位置。
    func scrollToVisible(_ view: NSView, animated: Bool = true) {
        guard let scrollView = enclosingScrollView else { return }
        layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        var target = clipView.convert(view.bounds, from: view)
        // 上下各留 8pt，避免目标刚好贴住视口边缘（贴边的卡片看起来像被切掉了）
        target = target.insetBy(dx: 0, dy: -8)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                clipView.animator().scrollToVisible(target)
            }
        } else {
            clipView.scrollToVisible(target)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    // MARK: 私有

    /// 追加到内容栈并设定「与上一个元素的间距」
    ///
    /// 间距挂在**前一个元素**的自定义间距上（NSStackView 只支持这一种表达），
    /// 所以是「先改上一个的间距，再加入新元素」。
    private func append(_ view: NSView, gapBefore: CGFloat, kind: ElementKind) {
        if let lastView {
            contentStack.setCustomSpacing(gapBefore, after: lastView)
        }
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        lastView = view
        lastKind = kind
    }

}
