import AppKit
import NetworkMonitorUI

// MARK: - 横向滚动跟随

/// 卡片流的「自由滚动」跟随 —— 从主文件拆出：主文件已顶到 15 KiB 单文件门禁，
/// 而这块是独立的一件事（视图池窗口跟着可视区走），不是布局本身的职责。
///
/// 改造前 windowStart 只由「选中项接近窗口边缘」驱动，自由滚动完全不管：
/// 用户把面板往左拖到第 33 条之后，那一段根本没有卡片视图，看起来就是一片空白。
extension ClipboardCardFlowView {

    // MARK: 子视图构建

    /// 卡片行的滚动容器 —— 刻意不给常驻滚动条：系统偏好设成「总是显示」时它会永久切走底部
    /// 十几 pt（卡片缩水 + 面板底部多一条灰带）；滚动改由触控板 / 滚轮 / 方向键承担。
    func buildScrollView() {
        scrollView.documentView = cardsContainer
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        addSubview(scrollView)
        observeHorizontalScroll()

        emptyView.isHidden = false
        cardsContainer.addSubview(emptyView)
    }

    /// 挂 clipView 的 bounds 观察者（buildScrollView 里调用一次）
    func observeHorizontalScroll() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.followVisibleRange() }
        }
    }

    /// 把视图池窗口挪到用户眼下看的那一段
    ///
    /// 窗口起点只按可视区算（多留一张在左侧，滚动手感不至于一卡一卡地补）。
    /// 刻意不在这里兜「选中项必须留在窗口内」：用户已经把那一张滚出屏幕了，再把窗口拽回选中项
    /// 会让滚动看起来像被钉住（第一版就踩了这个坑——选中默认在第 0 张，窗口每次都弹回 0，
    /// 滚动后仍然是空白）。选中项的可见性由方向键 / 点击 / 打开面板这些主动路径保证。
    func followVisibleRange() {
        guard !items.isEmpty, !isPlayingRemoval else { return }
        let span = cardSize.width + Self.spacing
        let offsetX = scrollView.contentView.bounds.minX
        let firstVisible = Int(floor(max(0, offsetX - Self.insetX) / span))
        let capacity = min(ClipboardCardWindowPolicy.windowSize, items.count)
        let maxStart = max(0, items.count - capacity)
        let start = min(max(0, firstVisible - 1), maxStart)
        guard start != windowStart else { return }
        setWindowStart(start)
        syncCards()
        needsLayout = true
    }

    // MARK: 滚轮 → 横向位移

    /// 没有常驻滚动条时，纵向滚轮 / 触控板上下滑折算成「横向翻卡片」；
    /// 横向手势与没有溢出可滚时原样交给 NSScrollView（免得同一段位移算两遍）
    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        let clip = scrollView.contentView
        let maxX = max(0, cardsContainer.frame.width - clip.bounds.width)
        guard abs(event.scrollingDeltaX) < abs(dy), dy != 0, maxX > 0 else {
            return super.scrollWheel(with: event)
        }
        // 精确设备（触控板）的 delta 已是点；传统滚轮一格约 1 行，乘 10 才有手感
        var origin = clip.bounds.origin
        origin.x = min(max(0, origin.x - (event.hasPreciseScrollingDeltas ? dy : dy * 10)), maxX)
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }
}
