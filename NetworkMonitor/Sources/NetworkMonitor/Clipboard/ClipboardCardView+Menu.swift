import AppKit

// MARK: - 卡片右键菜单

/// 右键菜单 — 顺序固定，除「贴到屏幕」走 onPin 外全部转交面板内容视图的指令通道
/// 跨文件访问：`item` / `onPin` / `menuEntry` 放宽 internal。
extension ClipboardCardView {

    /// 右键菜单（顺序固定）：复制 / 复制识别文字（仅图片）/ 粘贴为纯文本 / 编辑… / 收藏 / 移到板… / 贴到屏幕 / 删除…
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(menuEntry(.copy, title: "复制"))
        addOCRMenuEntryIfNeeded(to: menu)
        menu.addItem(menuEntry(.pastePlainText, title: "粘贴为纯文本"))
        menu.addItem(menuEntry(.edit, title: "编辑…"))
        menu.addItem(menuEntry(.togglePin, title: isPinned ? "取消收藏" : "收藏", state: isPinned ? .on : .off))
        menu.addItem(makeMoveToBoardMenu())   // 子菜单本体见 ClipboardCardMoveMenu.swift
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

    /// 菜单项构造：target 置空 = 沿响应链找到面板内容视图；representedObject 带条目 ID
    // 放宽为 internal：识别文字菜单项在 `ClipboardOCRMenu.swift`
    func menuEntry(_ command: ClipboardCardMenuCommand, title: String,
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
