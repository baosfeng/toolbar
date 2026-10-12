import AppKit
import NetworkMonitorCore

// MARK: - 卡片流容器

/// 卡片流容器 — 翻转坐标系，让内容从顶部开始排布
private final class ClipboardCardFlowContainer: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 卡片流视图

/// 卡片流视图 — 单行横向滚动 + 视图池 + 滑动窗口
///
/// 三层各有界，互不牵连：
/// 1. 布局：卡片单行横向排列，容器宽度 = 条目数 ×（卡宽 + 间距），只横向滚动，不换行、不纵向滚动；
/// 2. 视图：同一时刻最多存在 `windowSize` 张卡片视图 —— 数量不足才补建、多余只隐藏，
///    已存在的视图只做 `configure(with:isSelected:)` 与 frame 重设，禁止全删全建；
/// 3. 窗口：`windowStart` 决定当前建的是哪一段条目；选中项接近窗口边缘时窗口滑动到新位置并复用视图，
///    因此 `items` 可以是全部匹配项（上限由偏好 maxItems 决定），任意条数都能靠方向键走到。
@MainActor
final class ClipboardCardFlowView: NSView {

    /// 视图窗口大小：同一时刻最多保留的卡片视图数量（决定建视图开销与内存上限）
    static let windowSize = 120
    /// 窗口边缘缓冲：选中项落在窗口两端这么多条以内时滑动窗口
    private static let windowMargin = 8
    /// 卡片间距
    private static let spacing: CGFloat = 14
    /// 卡片流左右内边距
    private static let insetX: CGFloat = 12
    /// 卡片流上下内边距
    private static let insetY: CGFloat = 2

    /// 卡片被点选（参数为条目在 items 中的下标）
    var onSelect: ((Int) -> Void)?
    /// 卡片被双击（参数同上）
    var onActivate: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let cardsContainer = ClipboardCardFlowContainer()
    private let emptyLabel = NSTextField(labelWithString: "暂无剪贴板记录")
    /// 视图池：只增不减，靠 isHidden 与内容重设实现复用
    private var cardViews: [ClipboardCardView] = []
    /// 全部匹配项（视图只覆盖 windowStart 起的一段）
    private var items: [ClipboardItem] = []
    /// 窗口起点（items 中的全局下标）
    private var windowStart = 0
    /// 当前选中下标
    private var selectedIndex = -1

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildScrollView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 对外接口

    /// 重建卡片流（items 为全部匹配项；视图只覆盖窗口内的那一段）
    func render(items: [ClipboardItem], selectedIndex: Int) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.windowStart = 0
        slideWindow(force: true)
        syncCards(animated: false)
        emptyLabel.isHidden = !items.isEmpty
        needsLayout = true
        layoutSubtreeIfNeeded()
        scrollToSelection()
    }

    /// 仅切换选中态（方向键移动时复用卡片，不重建；必要时滑动窗口）
    func updateSelection(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        selectedIndex = index
        slideWindow(force: false)
        syncCards(animated: true)
        layoutCards()
        scrollToSelection()
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutCards()
    }

    /// 单行横向摆放：卡片 frame 由全局下标决定，容器宽度覆盖全部条目
    private func layoutCards() {
        let contentSize = scrollView.contentSize
        let cardSize = ClipboardCardView.cardSize
        let count = visibleCount()
        for (slot, card) in cardViews.enumerated() where slot < count {
            card.frame = NSRect(x: Self.insetX + CGFloat(windowStart + slot) * (cardSize.width + Self.spacing),
                                y: Self.insetY, width: cardSize.width, height: cardSize.height)
        }
        let allWidth = Self.insetX * 2 + CGFloat(items.count) * (cardSize.width + Self.spacing)
        cardsContainer.frame = NSRect(x: 0, y: 0,
                                      width: max(contentSize.width, allWidth),
                                      height: max(contentSize.height, cardSize.height + Self.insetY * 2))
        emptyLabel.frame = NSRect(x: 0, y: max(0, (contentSize.height - 20) / 2), width: contentSize.width, height: 20)
    }

    /// 窗口滑动：选中项接近窗口边缘时把窗口重新居中到选中项，保证任意下标都能走到
    private func slideWindow(force: Bool) {
        let count = items.count
        guard count > Self.windowSize else { windowStart = 0; return }
        let selected = max(0, selectedIndex)
        let inside = selected >= windowStart + Self.windowMargin
            && selected < windowStart + Self.windowSize - Self.windowMargin
        guard force || !inside else { return }
        windowStart = min(max(0, selected - Self.windowSize / 2), count - Self.windowSize)
    }

    /// 当前窗口内应收纳的卡片数
    private func visibleCount() -> Int {
        min(max(0, items.count - windowStart), Self.windowSize)
    }

    // MARK: 视图池

    /// 同步视图池：不足补建、多余隐藏，已存在的仅重设内容与选中态（禁止全删全建）
    private func syncCards(animated: Bool) {
        let count = visibleCount()
        while cardViews.count < count { cardViews.append(makeCardView()) }
        for (slot, card) in cardViews.enumerated() {
            guard slot < count else { card.isHidden = true; continue }
            let index = windowStart + slot
            card.isHidden = false
            let item = items[index]
            if card.item?.id == item.id {
                card.setSelected(index == selectedIndex, animated: animated)
            } else {
                card.configure(with: item, isSelected: index == selectedIndex)
            }
        }
    }

    /// 新建一张卡片视图；回调按视图在池中的槽位换算当前下标（视图复用后下标随之变化）
    private func makeCardView() -> ClipboardCardView {
        let card = ClipboardCardView(frame: NSRect(origin: .zero, size: ClipboardCardView.cardSize))
        card.onClick = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onSelect?(self.windowStart + index)
        }
        card.onDoubleClick = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onActivate?(self.windowStart + index)
        }
        cardsContainer.addSubview(card)
        return card
    }

    /// 把选中卡片滚进可视区（选中项必在窗口内，故按槽位直接取）
    private func scrollToSelection() {
        let slot = selectedIndex - windowStart
        guard slot >= 0, slot < visibleCount() else { return }
        let card = cardViews[slot]
        card.scrollToVisible(card.bounds.insetBy(dx: -16, dy: -16))
    }

    // MARK: 子视图构建

    private func buildScrollView() {
        scrollView.documentView = cardsContainer
        // 单行横向滚动：只开横向滚动条，纵向滚动保持关闭
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        addSubview(scrollView)

        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        cardsContainer.addSubview(emptyLabel)
    }
}
