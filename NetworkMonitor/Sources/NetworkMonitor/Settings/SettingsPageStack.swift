import AppKit
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

        // 标题行：标题 + 状态胶囊（贴在标题右侧，不推到最右——胶囊属于标题而不是右侧操作）
        let titleRow = NSStackView(views: [titleLabel, statusChipView, MenuPanelLabel.spacer()])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = SettingsTheme.statusChipSpacing
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let header = NSStackView(views: [titleRow, subtitleLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 3
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
            let header = makeGroupHeader(title: sectionTitle, trailingAccessory: trailingAccessory)
            append(header, gapBefore: SettingsTheme.groupSpacingTop, kind: .group)
            append(card, gapBefore: SettingsTheme.groupSpacingBottom, kind: .card)
        } else {
            let gap = lastKind == .header ? SettingsTheme.groupSpacingTop : SettingsTheme.cardSpacing
            append(card, gapBefore: gap, kind: .card)
        }
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

    /// 分组标题行 —— 11.5pt semibold 次级色，中文**不转大写**；左右内缩 2pt
    ///
    /// 为什么比面板多这一层：一屏 5 组内容需要分区，它的字号仍是面板
    /// 「11pt 粗 + 次级色」的同一档，只是窗口尺度上调到 11.5。
    private func makeGroupHeader(title: String, trailingAccessory: NSView?) -> NSView {
        let label = MenuPanelLabel.text(title, font: SettingsTheme.sectionTitleFont,
                                        color: SettingsTheme.textSecondary)
        var views: [NSView] = [label]
        if let trailingAccessory {
            views.append(MenuPanelLabel.spacer())
            views.append(trailingAccessory)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor,
                                         constant: SettingsTheme.groupTitleInset),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }
}
