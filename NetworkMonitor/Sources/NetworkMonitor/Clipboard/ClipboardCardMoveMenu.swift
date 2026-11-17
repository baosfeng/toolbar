import AppKit
import NetworkMonitorCore

// MARK: - 卡片右键「移到板…」子菜单

/// 「移到板…」—— 单独成文件：卡片菜单所属族的合计只允许变小，板选择是新领域，
/// 整段逻辑落在这里，`ClipboardCardView+Menu.swift` 只留一行挂载。
///
/// 子项不走 `ClipboardCardMenuCommand` 的 tag 通道：那条通道只带条目 ID，
/// 这里还要带目标板，故用 `ClipboardBoardMoveTarget` 一并携带，由面板视图单独分发。
extension ClipboardCardView {

    /// 构造「移到板…」：首项恒为「移出板」，其后按板的展示顺序列出各板
    func makeMoveToBoardMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "移到板…", action: nil, keyEquivalent: "")
        // tag 与枚举对齐：菜单顺序表里「移到板…」占一席，便于探针按 tag 对账
        root.tag = ClipboardCardMenuCommand.moveToBoard.rawValue
        let submenu = NSMenu()
        // 「移出板」置顶：批量移出与移入走同一入口，不必先切到别的板再找
        submenu.addItem(moveEntry(title: "移出板", boardID: nil))
        for board in enclosingPanelView?.moveBoards ?? [] {
            submenu.addItem(moveEntry(title: board.name, boardID: board.id))
        }
        root.submenu = submenu
        return root
    }

    /// 单个目标项：target 置空 = 沿响应链落到面板内容视图；representedObject 带条目与目标板
    private func moveEntry(title: String, boardID: UUID?) -> NSMenuItem {
        let entry = NSMenuItem(title: title,
                               action: #selector(ClipboardPanelView.handleCardMoveToBoard(_:)),
                               keyEquivalent: "")
        entry.target = nil
        entry.representedObject = ClipboardBoardMoveTarget(itemID: item?.id, boardID: boardID)
        return entry
    }

    /// 沿响应链上溯到面板内容视图（视图的 nextResponder 即父视图），取不到就只列「移出板」
    private var enclosingPanelView: ClipboardPanelView? {
        var node: NSResponder? = nextResponder
        while let current = node {
            if let panel = current as? ClipboardPanelView { return panel }
            node = current.nextResponder
        }
        return nil
    }
}

// MARK: - 菜单项携带的目标

/// 「移到板…」子项的目标：条目（nil = 卡片尚未配置内容）+ 目标板（nil = 移出板）
struct ClipboardBoardMoveTarget {
    let itemID: UUID?
    let boardID: UUID?
}

// MARK: - 面板视图侧：板清单与分发

extension ClipboardPanelView {

    /// 菜单要列的板（标签行里已经排好的那批，视图不另查库）
    var moveBoards: [ClipboardBoard] { boardRowView.boards }

    /// 「移到板…」分发：只把目标交给控制器，批量口径由控制器按多选状态决定
    @objc func handleCardMoveToBoard(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? ClipboardBoardMoveTarget,
              let itemID = target.itemID else { return }
        delegate?.panelView(self, didRequestMoveToBoard: target.boardID, itemID: itemID)
    }
}
