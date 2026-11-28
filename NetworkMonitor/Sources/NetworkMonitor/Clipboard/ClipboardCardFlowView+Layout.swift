import AppKit
import NetworkMonitorUI

// MARK: - 卡片流布局（从主文件拆出，守住 15 KiB 上限）
//
// 单行摆放 / 窗口起点 / 投影矩形：同一份几何口径算出的 frame，放一起改才不会「卡片挪了阴影没挪」。

extension ClipboardCardFlowView {
    /// 单行横向摆放：卡片 frame 由全局下标决定，容器宽度覆盖全部条目；卡片在可视高度内垂直居中
    func layoutCards() {
        let contentSize = scrollView.contentSize
        // 按「滚动视图真正能显示的高度」算：滚动条常显时它会切走底部一条，用 bounds 算会被裁卡脚
        let visibleHeight = contentSize.height > 1 ? min(bounds.height, contentSize.height) : bounds.height
        let cardSize = ClipboardCardGeometry.cardSize(forCardAreaHeight: visibleHeight)
        self.cardSize = cardSize
        let count = visibleCount()
        // 顶部对齐：卡片贴着工具条下沿，多余的卡片区高度全留给底部
        // （状态胶囊浮在那条带里；垂直居中会让「底部长出半截空白」，与 Paste 的贴顶排布不一致）
        let cardY = ClipboardCardGeometry.cardInsetTop
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
                                      height: max(contentSize.height,
                                                  cardSize.height + ClipboardCardGeometry.cardSlack))
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
}
