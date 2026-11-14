import AppKit

// MARK: - 面板快照取证（仅 DEBUG）

/// 快照自证专用入口 —— 从 `MenuPanelView` 主文件拆出
///
/// 拆出理由：主文件已到 12 KiB 量级（单文件 15 KiB 门禁），这批方法只在 DEBUG 下
/// 给离屏快照与像素量测用，与面板运行逻辑无关，混在一起只会把主文件顶出门禁。
#if DEBUG
extension MenuPanelView {

    /// 取证专用构造：建面板并把六个分页一次装配好
    ///
    /// 离线取证普遍是「先推数据、再切页」（`updateToken` → `select(tab:)`），懒装配会把
    /// 未切到页的数据丢掉，取出来的图就是空的；取证路径显式装配全部六页，
    /// 保持与改造前一致的取图结果（真实运行路径仍是首次切到才建）。
    static func evidencePanel() -> MenuPanelView {
        let panel = MenuPanelView()
        for tab in MenuPanelTab.allCases {
            panel.ensurePaneLoaded(tab)
        }
        return panel
    }

    /// 返回（文档高度, 滚动视口高度）
    func snapshotScrollMetrics() -> (document: CGFloat, viewport: CGFloat) {
        layoutSubtreeIfNeeded()
        return (paneStack.frame.height, scrollView.contentView.bounds.height)
    }

    /// 把内容滚到指定比例（0 = 顶部，1 = 底部）
    func scrollForSnapshot(fraction: CGFloat) {
        layoutSubtreeIfNeeded()
        let maxY = max(0, paneStack.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY * min(max(fraction, 0), 1)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 滚到内容底部
    func scrollToBottomForSnapshot() {
        layoutSubtreeIfNeeded()
        let maxY = max(0, paneStack.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
#endif
