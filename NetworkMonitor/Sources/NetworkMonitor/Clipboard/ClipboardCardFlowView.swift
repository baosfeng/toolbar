import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片流视图

/// 卡片流视图 — 单行横向滚动 + 视图池 + 滑动窗口
///
/// 三层各有界，互不牵连：
/// 1. 布局：卡片单行横向排列，容器宽度 = 条目数 ×（卡宽 + 间距），只横向滚动，不换行、不纵向滚动；
/// 2. 视图：同一时刻最多存在 `ClipboardCardWindowPolicy.windowSize` 张卡片视图 —— 数量不足才补建、多余只隐藏，
///    已存在的视图只做 `configure(with:isSelected:number:)` 与 frame 重设，禁止全删全建；
/// 3. 窗口：`windowStart` 决定当前建的是哪一段条目；选中项接近窗口边缘时窗口滑动到新位置并复用视图，
///    因此 `items` 可以是全部匹配项（上限由偏好 maxItems 决定），任意条数都能靠方向键走到。
///
/// 拆文件口径：容器与空态在 `ClipboardCardFlowChrome.swift`，缩略图在
/// `ClipboardCardFlowView+Thumbnails.swift`，动效在 `ClipboardCardFlowView+Motion.swift`。
/// 全文不再有悬停浮层：选中项的完整内容常驻在面板底部的详情区（`ClipboardDetailStripView`）。
@MainActor
final class ClipboardCardFlowView: NSView {

    /// 卡片间距（12pt：三段式卡片之间要更多呼吸，10pt 时卡头色带几乎连成一条）
    // 放宽为 internal：滚动跟随扩展（+ScrollFollow）按同一套间距算窗口起点
    static let spacing: CGFloat = 12
    /// 卡片流左右内边距
    static let insetX: CGFloat = 10
    /// 打开面板后预取的图片条目条数（增量规格 2.2 第 4 条）
    static let prefetchImageCount = 12

    /// 卡片被点选（参数为条目在 items 中的下标与点击语义：替换 / ⌘ 切换 / ⇧ 范围选）
    var onSelect: ((Int, ClipboardSelectionModel.Click) -> Void)?
    /// 卡片右键「贴到屏幕」回调（索引为全量列表下标）
    var onPin: ((Int) -> Void)?
    /// 卡片被双击（参数同上）
    var onActivate: ((Int) -> Void)?
    /// 选中项发生切换（面板控制器在此接触觉反馈；未注入时静默）
    var onSelectionChanged: (() -> Void)?

    /// 缩略图就绪通知的观察者（主线程回调；deinit 时移除）
    /// nonisolated(unsafe)：deinit 不在主 actor 上，移除观察者需要直接读它
    nonisolated(unsafe) var thumbnailObserver: NSObjectProtocol?
    /// 横向滚动通知的观察者 —— 视图池窗口必须跟着可视区走，否则用户滚出窗口就是一片空白
    nonisolated(unsafe) var scrollObserver: NSObjectProtocol?
    /// 面板上屏通知的观察者（每次面板打开播一次卡片错峰进场）
    nonisolated(unsafe) var onScreenObserver: NSObjectProtocol?

    // 放宽为 internal：滚动跟随扩展（+ScrollFollow）要挂 bounds 观察者
    let scrollView = NSScrollView()
    private let cardsContainer = ClipboardCardFlowContainer()
    private let emptyView = ClipboardEmptyStateView(message: "没有匹配的剪贴板条目")

    /// 视图池：只增不减，靠 isHidden 与内容重设实现复用
    /// （internal：删除动效与进场动效在 ClipboardCardFlowView+Motion.swift 里操作它）
    var cardViews: [ClipboardCardView] = []
    /// 全部匹配项（视图只覆盖 windowStart 起的一段；internal：动效扩展要比对旧列表）
    var items: [ClipboardItem] = []
    /// 窗口起点（items 中的全局下标）
    private(set) var windowStart = 0
    /// 当前选中下标（internal：多选渲染与动效扩展都要读写焦点）
    var selectedIndex = -1
    /// 当前选中条目集合（多选态可能有多个；空集合 = 没有任何卡片选中）
    var selectedIDs: Set<UUID> = []
    /// 当前搜索查询（空串 = 不高亮）——每次落地渲染时同步给窗口内每张卡
    private(set) var highlightQuery: String = ""

    /// 设置搜索高亮查询：只在变化时重绘（清空查询即回到无高亮）
    func setHighlightQuery(_ query: String) {
        guard query != highlightQuery else { return }
        highlightQuery = query
        for card in cardViews { card.highlightQuery = query }
        needsDisplay = true
    }

    /// 删除动效排队中的下一次渲染（动效结束后才真正重排）
    private var pendingRender: (items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>)?
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
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    // MARK: 对外接口

    /// 暂存一次渲染：删除动效期间到达的渲染只排队，结束回调里一次性落地
    func stageRender(items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>) {
        pendingRender = (items, selectedIndex, selectedIDs)
        isPlayingRemoval = true
    }

    /// 动效结束后落地暂存的渲染（没有暂存就什么都不做）
    func finishStagedRender() {
        isPlayingRemoval = false
        guard let pending = pendingRender else { return }
        pendingRender = nil
        apply(items: pending.items, selectedIndex: pending.selectedIndex, selectedIDs: pending.selectedIDs)
    }

    /// 真正落地一次渲染（含错峰进场；多选渲染入口见 ClipboardCardSelectionFlow.swift）
    func apply(items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.selectedIDs = selectedIDs
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
    func layoutCards() {
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
        refreshShadows()
    }

    /// 改写窗口起点（滚动跟随扩展用：windowStart 在本文件是 private(set)）
    ///
    /// 只有「自由横向滚动」这一条路径该改它；方向键 / 点击 / 打开面板仍走 slideWindow。
    func setWindowStart(_ value: Int) {
        windowStart = max(0, value)
    }

    /// 把「hover 或选中的可见卡片」交给容器绘制投影（未选中的卡片不投影，避免整屏噪声）
    ///
    /// 阴影由容器统一画（见 ClipboardCardFlowContainer）：卡片自身的 draw 画不到卡外，
    /// 而卡片 backing layer 的阴影在离屏快照路径里不参与合成。
    func refreshShadows() {
        cardsContainer.shadowRects = cardViews
            .filter { !$0.isHidden && !$0.isRemoving && ($0.isSelected || $0.isHovering) }
            .map { $0.frame }
    }

    /// 窗口滑动：选中项接近窗口边缘时把窗口重新居中到选中项，保证任意下标都能走到
    ///
    /// 算术在 `ClipboardCardWindowPolicy`（纯函数，TestRunner 覆盖 0…N 全下标可达性）。
    func slideWindow(force: Bool) {
        windowStart = ClipboardCardWindowPolicy.windowStart(itemCount: items.count,
                                                           selectedIndex: selectedIndex,
                                                           currentStart: windowStart,
                                                           force: force)
    }

    /// 当前窗口内应收纳的卡片数（internal：缩略图扩展按它裁可见卡片）
    func visibleCount() -> Int {
        ClipboardCardWindowPolicy.visibleCount(itemCount: items.count, windowStart: windowStart)
    }

    // MARK: 视图池

    /// 同步视图池：不足补建、多余隐藏，已存在的仅重设内容与选中态（禁止全删全建）
    func syncCards() {
        let count = visibleCount()
        while cardViews.count < count { cardViews.append(makeCardView()) }
        for (slot, card) in cardViews.enumerated() {
            guard slot < count else { card.isHidden = true; continue }
            let index = windowStart + slot
            card.isHidden = false
            let item = items[index]
            // 多选态按集合判定：选中项可以有多张卡，但不能没有焦点（焦点由窗口保证可见）
            let targetSelected = selectedIDs.contains(item.id)
            // 内容、收藏态、栈位置都没变、只有选中态变了：走轻量路径，只做描边与底色的交叉过渡，
            // 不重设正文与缩略图（方向键连按时这条路径承担绝大部分切换）
            let sameContent = card.item?.id == item.id
                && card.item?.isPinned == item.isPinned
                && card.item?.stackPosition == item.stackPosition
                && card.showsShortcut == (selectedIDs.count <= 1)   // 进出多选要重设角标
            if sameContent {
                if card.isSelected != targetSelected { card.setSelected(targetSelected) }
                continue
            }
            // ⌘1–9 角标只在单选态出现：多选时直选语义不适用，角标会误导
            card.configure(with: item, isSelected: targetSelected, number: index + 1,
                           showsShortcut: selectedIDs.count <= 1)
            // 复用卡可能是上一次查询的旧高亮：配置时无条件对齐当前查询
            card.highlightQuery = highlightQuery
        }
        refreshShadows()
    }

    /// 新建一张卡片视图；回调按视图在池中的槽位换算当前下标（视图复用后下标随之变化）
    private func makeCardView() -> ClipboardCardView {
        let card = ClipboardCardView(frame: NSRect(origin: .zero, size: ClipboardCardView.cardSize))
        card.onPin = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(where: { $0 === card }) else { return }
            self.onPin?(self.windowStart + index)
        }
        card.onClickWithModifiers = { [weak self] card, click in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onSelect?(self.windowStart + index, click)
        }
        card.onDoubleClick = { [weak self] card in
            guard let self, let index = self.cardViews.firstIndex(of: card) else { return }
            self.onActivate?(self.windowStart + index)
        }
        card.onShadowStateChange = { [weak self] in self?.refreshShadows() }
        attachDragProvider(to: card)
        cardsContainer.addSubview(card)
        return card
    }

    /// 把选中卡片滚进可视区（选中项必在窗口内，故按槽位直接取）
    func scrollToSelection() {
        let slot = selectedIndex - windowStart
        guard slot >= 0, slot < visibleCount() else { return }
        let card = cardViews[slot]
        card.scrollToVisible(card.bounds.insetBy(dx: -16, dy: -16))
    }

    // MARK: 生命周期

    /// 换窗口时重挂通知：离开窗口（面板收起 / 快照结束）复位进场中间态与进场订阅
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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
        // 视图池只覆盖 windowStart 起的一段；自由横向滚动时必须把窗口跟着挪过去（见 +ScrollFollow）
        observeHorizontalScroll()

        emptyView.isHidden = false
        cardsContainer.addSubview(emptyView)
    }
}