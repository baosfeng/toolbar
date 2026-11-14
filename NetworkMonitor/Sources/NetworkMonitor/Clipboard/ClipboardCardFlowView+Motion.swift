import AppKit
import NetworkMonitorCore

// MARK: - 卡片流动效

/// `ClipboardCardFlowView` 的动效接线 — 进场错峰、删除缩小淡出、缩略图淡入与 hover 浮层
///
/// 动效本体全部走 `MotionKit`，本文件只负责「什么时候播、播在谁身上」：
/// - 进场：每次重建（`render`）后前 12 张按 0.024s 错峰淡入，累计不超过 0.3s；
/// - 删除：条目消失时先在原位置缩到 0.9 并淡出（0.15s），动效结束再重排，避免卡片硬跳；
/// - 缩略图：就绪回调改为 0.2s 淡入替换占位符号，不改卡片内容；
/// - hover 浮层：悬停满 0.45s 由卡片回调触发，移出即收。
///
/// 跨文件访问：`items` / `windowStart` / `selectedIndex` / `cardViews` / `visibleCards()` /
/// `showFullTextOverlay` / `hideFullTextOverlay` 由主文件放宽为 internal。
extension ClipboardCardFlowView {

    /// 进场动画覆盖的最大卡片数（设计规格 §3.2 B2：前 12 张错峰）
    static var entranceCardLimit: Int { 12 }

    /// 收集「新列表里已不存在」的可见卡片（删除动效的对象）
    func vanishedCards(newItems: [ClipboardItem]) -> [ClipboardCardView] {
        let alive = Set(newItems.map(\.id))
        return visibleCards().filter { card in
            guard let item = card.item else { return false }
            return !alive.contains(item.id)
        }
    }

    /// 播放删除动效：卡片原地缩小 + 淡出，全部结束后回调（由调用方触发重排）
    func playRemoval(on cards: [ClipboardCardView], completion: @escaping () -> Void) {
        guard MotionKit.isEnabled, !cards.isEmpty else {
            completion()
            return
        }
        var remaining = cards.count
        for card in cards {
            card.playRemoval {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }

    /// 进场：前 12 张按错峰延迟淡入（总时长由 MotionKit.stagger 封顶 0.3s）
    ///
    /// 开播前先把窗口内的卡片复位到不透明，保证「上次被打断」的残留状态不会带进新一轮。
    func playEntrance() {
        for card in visibleCards() { card.alphaValue = 1 }
        let limit = min(visibleCards().count, Self.entranceCardLimit)
        for slot in 0..<limit {
            let card = cardViews[slot]
            guard !card.isRemoving else { continue }
            MotionKit.fadeIn(card, offsetY: 8, delay: MotionKit.stagger(index: slot))
        }
    }

    /// 缩略图就绪：命中卡片淡入真图（0.2s），不再硬替换
    func applyThumbnail(hash: String) {
        for card in visibleCards() where card.item?.contentHash == hash {
            card.refreshThumbnail(animated: true)
        }
    }

    /// hover 浮层：显示卡片全文，移出即收
    func showFullTextOverlay(for card: ClipboardCardView) {
        guard let item = card.item, window?.isVisible == true else { return }
        ClipboardCardFullTextOverlay.shared.show(item: item, anchor: card)
    }

    /// 收起浮层（只有归属该卡片的浮层才收；owner 为 nil 时无条件收）
    func hideFullTextOverlay(owner: ClipboardCardView?) {
        ClipboardCardFullTextOverlay.shared.hide(ifOwner: owner)
    }
}