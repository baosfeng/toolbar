import AppKit

// MARK: - 卡片右键菜单

/// `ClipboardCardView` 的右键菜单 — 5 项固定顺序，全部转交面板内容视图的指令通道
///
/// 跨文件访问：`item` / `onPin` 由主文件放宽为 internal（无其他调用方）。
/// 分发口径：除「贴到屏幕」沿用既有 onPin 贴图链路外，其余四项统一交给面板内容视图的
/// 菜单指令通道（响应链 → 控制器既有动作），保证不存在第二套复制 / 粘贴实现。
extension ClipboardCardView {

    /// 右键菜单 5 项（顺序固定）：复制 / 粘贴为纯文本 / 收藏 / 贴到屏幕 / 删除…
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuEntry(.copy, title: "复制"))
        menu.addItem(menuEntry(.pastePlainText, title: "粘贴为纯文本"))
        menu.addItem(menuEntry(.togglePin, title: isPinned ? "取消收藏" : "收藏", state: isPinned ? .on : .off))
        let screenEntry = NSMenuItem(title: "贴到屏幕", action: #selector(menuPinToScreen), keyEquivalent: "")
        screenEntry.target = self
        menu.addItem(screenEntry)
        menu.addItem(menuEntry(.delete, title: "删除…"))
        return menu
    }

    /// 当前条目是否已收藏（菜单标题与勾选态据此决定）
    private var isPinned: Bool { item?.isPinned ?? false }

    @objc private func menuPinToScreen() {
        onPin?(self)
    }

    /// 菜单项构造：target 置空 = 沿响应链找到面板内容视图；representedObject 带条目 ID，
    /// 由控制器按 ID 换算下标，避免依赖卡片池的视图位置
    private func menuEntry(_ command: ClipboardCardMenuCommand, title: String,
                           state: NSControl.StateValue = .off) -> NSMenuItem {
        let entry = NSMenuItem(title: title,
                               action: #selector(ClipboardPanelView.handleCardMenuCommand(_:)),
                               keyEquivalent: "")
        entry.target = nil
        entry.tag = command.rawValue
        entry.state = state
        entry.representedObject = item?.id
        return entry
    }
}
