import AppKit
import NetworkMonitorCore

// MARK: - 卡片流视图

/// 卡片流视图 — 单行横向滚动 + 视图池 + 滑动窗口
///
/// 三层各有界，互不牵连：
/// 1. 布局：卡片单行横向排列，容器宽度 = 条目数 ×（卡宽 + 间距），只横向滚动，不换行、不纵向滚动；
/// 2. 视图：同一时刻最多存在 `windowSize` 张卡片视图 —— 数量不足才补建、多余只隐藏，
///    已存在的视图只做 `configure(with:isSelected:number:)` 与 frame 重设，禁止全删全建；
/// 3. 窗口：`windowStart` 决定当前建的是哪一段条目；选中项接近窗口边缘时窗口滑动到新位置并复用视图，
///    因此 `items` 可以是全部匹配项（上限由偏好 maxItems 决定），任意条数都能靠方向键走到。
///
/// 拆文件口径：容器与空态在 `ClipboardCardFlowChrome.swift`，缩略图在
/// `ClipboardCardFlowView+Thumbnails.swift`，动效与 hover 浮层在
/// `ClipboardCardFlowView+Motion.swift`。
@MainActor
final class ClipboardCardFlowView: NSView {

    /// 视图窗口大小：同一时刻最多保留的卡片视图数量（决定建视图开销与内存上限）
    static let windowSize = 120
    /// 窗口边缘缓冲：选中项落在窗口两端这么多条以内时滑动窗口
    private static let windowMargin = 8
    /// 卡片间距（设计规格 10pt）
    private static let spacing: CGFloat = 10
    /// 卡片流左右内边距
    private static let insetX: CGFloat = 10
    /// 打开面板后预取的图片条目条数（增量规格 2.2 第 4 条）
    static let prefetchImageCount = 12

    /// 卡片被点选（参数为条目在 items 中的下标）
    var onSelect: ((Int) -> Void)?
    /// 卡片右键「贴到屏幕」回调（索引为全量列表下标）
    var onPin: ((Int) -> Void)?
    /// 卡片被双击（参数同上）
    var onActivate: ((Int) -> Void)?
    /// 选中项发生切换（面板控制器在此接触觉反馈；未注入时静默）
    var onSelectionChanged: (() -> Void)?

    /// 缩略图就绪通知的观察者（主线程回调；deinit 时移除）
    /// nonisolated(unsafe)：deinit 不在主 actor 上，移除观察者需要直接读它
    nonisolated(unsafe) var thumbnailObserver: NSObjectProtocol?
    /// 面板上屏通知的观察者（每次面板打开播一次卡片错峰进场）
    nonisolated(unsafe) var onScreenObserver: NSObjectProtocol?

    private let scrollView = NSScrollView()
    private let cardsContainer = ClipboardCardFlowContainer()
    private let emptyView = ClipboardEmptyStateView(message: "没有匹配的剪贴板条目")

    /// 视图池：只增不减，靠 isHidden 与内容重设实现复用
    /// （internal：删除动效与进场动效在 ClipboardCardFlowView+Motion.swift 里操作它）
    var cardViews: [ClipboardCardView] = []
    /// 全部匹配项（视图只覆盖 windowStart 起的一段；internal：动效扩展要比对旧列表）
    var items: [ClipboardItem] = []
    /// 窗口起点（items 中的全局下标）
    private(set) var windowStart = 0
    /// 当前选中下标（internal：动效扩展读当前选中）
    private(set) var selectedIndex = -1

    /// 删除动效排队中的下一次渲染（动效结束后才真正重排）
    private var pendingRender: (items: [ClipboardItem], selectedIndex: Int)?
    /// 删除动效是否在播（期间到达的新渲染参数只排队，不并发）
    private(set) var isPlayingRemoval = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildScrollView()
        observeThumbnails()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    nonisolated deinit {
        if let thumbnailObserver { NotificationCenter.default.removeObserver(thumbnailObserver) }
        if let onScreenObserver { NotificationCenter.default.removeObserver(onScreenObserver) }
    }

    // MARK: 对外接口

    /// 重建卡片流（items 为全部匹配项；视图只覆盖窗口内的那一段）
    ///
    /// 只有「单条删除」才先播删除动效（0.15s 缩小 + 淡出）再重排；
    /// 过滤切换 / 清空历史属于整屏重排，直接落地并播进场错峰淡入。
    func render(items: [ClipboardItem], selectedIndex: Int) {
        let removed = isPlayingRemoval ? [] : vanishedCards(newItems: items)
        let vanished = (removed.count == 1 && items.count == self.items.count - 1) ? removed : []
        guard vanished.isEmpty else {
            pendingRender = (items, selectedIndex)
            isPlayingRemoval = true
            hideFullTextOverlay(owner: nil)
            playRemoval(on: vanished) { [weak self] in
                guard let self else { return }
                self.isPlayingRemoval = false
                guard let pending = self.pendingRender else { return }
                self.pendingRender = nil
                self.apply(items: pending.items, selectedIndex: pending.selectedIndex)
            }
            return
        }
        apply(items: items, selectedIndex: selectedIndex)
    }

    /// 仅切换选中态（方向键移动时复用卡片，不重建；必要时滑动窗口）
    func updateSelection(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        let previous = selectedIndex
        selectedIndex = index
        slideWindow(force: false)
        syncCards()
        layoutCards()
        scrollToSelection()
        // 换了选中项，全文浮层指向的已不是用户关注的那张卡片
        hideFullTextOverlay(owner: nil)
        if previous != selectedIndex { onSelectionChanged?() }
    }

    /// 真正落地一次渲染（含错峰进场）
    private func apply(items: [ClipboardItem], selectedIndex: Int) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.windowStart = 0
        slideWindow(force: true)
        syncCards()
        prefetchThumbnails()
        emptyView.isHidden = !items.isEmpty
        needsLayout = true
        layoutSubtreeIfNeeded()
        scrollToSelection()
        // 这里刻意不发 onSelectionChanged：整屏重排（打开面板 / 过滤切换 / 粘贴后刷新）
        // 不是用户切换选中项，触觉只由 updateSelection 那条路径（方向键、点击卡片）触发
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutCards()
    }

    /// 单行横向摆放：卡片 frame 由全局下标决定，容器宽度覆盖全部条目；卡片在可视高度内垂直居中
    private func layoutCards() {
        let contentSize = scrollView.contentSize
        let cardSize = ClipboardCardView.cardSize
        let count = visibleCount()
        let cardY = max(0, (contentSize.height - cardSize.height) / 2)
        for (slot, card) in cardViews.enumerated() where slot < count {
            card.frame = NSRect(x: Self.insetX + CGFloat(windowStart + slot) * (cardSize.width + Self.spacing),
                                y: cardY, width: cardSize.width, height: cardSize.height)
        }
        // 容器宽度必须覆盖「全部匹配项」而非当前窗口：窗口滑动后卡片仍按全局下标摆放
        let allWidth = Self.insetX * 2
            + CGFloat(items.count) * (cardSize.width + Self.spacing)
            - (items.isEmpty ? 0 : Self.spacing)
        cardsContainer.frame = NSRect(x: 0, y: 0,
                                      width: max(contentSize.width, allWidth),
                                      height: max(contentSize.height, cardSize.height))
        emptyView.frame = cardsContainer.bounds
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

    /// 当前窗口内应收纳的卡片数（internal：缩略图扩展按它裁可见卡片）
    func visibleCount() -> Int {
        min(max(0, items.count - windowStart), Self.windowSize)
    }

    // MARK: 视图池

    /// 同步视图池：不足补建、多余隐藏，已存在的仅重设内容与选中态（禁止全删全建）
    private func syncCards() {
        let count = visibleCount()
        while cardViews.count < count { cardViews.append(makeCardView()) }
        for (slot, card) in cardViews.enumerated() {
            guard slot < count else { card.isHidden = true; continue }
            let index = windowStart + slot
            card.isHidden = false
            let item = items[index]
            let targetSelected = index == selectedIndex
            // 内容、收藏态、栈位置都没变、只有选中态变了：走轻量路径，只做描边与底色的交叉过渡，
            // 不重设正文与缩略图（方向键连按时这条路径承担绝大部分切换）
            let sameContent = card.item?.id == item.id
                && card.item?.isPinned == item.isPinned
                && card.item?.stackPosition == item.stackPosition
            if sameContent {
                if card.isSelected != targetSelected { card.setSelected(targetSelected) }
                continue
            }
            card.configure(with: item, isSelected: targetSelected, number: index + 1)
        }
    }

    /// 新建一张卡片视图；回调按视图在池中的槽位换算当前下标（视图复用后下标随之变化）
    private func makeCardView() -> ClipboardCardView {
        let card = ClipboardCardView(frame: NSRect(origin: .zero, size: ClipboardCardView.cardSize))
        card.onPin = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(where: { $0 === card }) else { return }
            self.onPin?(self.windowStart + index)
        }
        card.onClick = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onSelect?(self.windowStart + index)
        }
        card.onDoubleClick = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onActivate?(self.windowStart + index)
        }
        card.onHoverStateChange = { [weak self] card, hovering in
            guard let self else { return }
            if hovering { self.showFullTextOverlay(for: card) } else { self.hideFullTextOverlay(owner: card) }
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

    // MARK: 鼠标

    /// 竖向滚轮：全文浮层开着且正文超长时，滚轮改由浮层吞掉（浮层自身不收鼠标事件，
    /// 只有这样才能既「不拦截点击」又「超长内容可滚」）
    override func scrollWheel(with event: NSEvent) {
        if ClipboardCardFullTextOverlay.shared.scroll(by: event.scrollingDeltaY) { return }
        super.scrollWheel(with: event)
    }

    // MARK: 生命周期

    /// 换窗口时重挂通知：离开窗口（面板收起 / 快照结束）收起全文浮层、复位进场中间态与进场订阅
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideFullTextOverlay(owner: nil)
        stopObservingOnScreen()
        guard let window else { resetCardsForNextEntrance(); return }
        // 面板每次打开（makeKeyAndOrderFront 触发 didBecomeKey）播一次卡片错峰进场；
        // 离屏快照 / 预布局不触发这条通知，截图里不会留半透明卡片
        onScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playEntrance() }
        }
    }

    /// 复位卡片到「不透明、无缩放、无位移」：进场动效中途收起面板时，卡片可能停在半透明，
    /// 下一次打开若内容未变就不会重新 configure，必须在这里兜底复位
    private func resetCardsForNextEntrance() {
        for card in cardViews {
            card.alphaValue = 1
            card.layer?.transform = CATransform3DIdentity
        }
    }

    /// 摘掉上屏观察者（换窗口 / 被移出窗口时都要清，避免旧窗口继续驱动本视图）
    private func stopObservingOnScreen() {
        if let onScreenObserver { NotificationCenter.default.removeObserver(onScreenObserver) }
        onScreenObserver = nil
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

        emptyView.isHidden = false
        cardsContainer.addSubview(emptyView)
    }
}