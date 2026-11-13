import AppKit
import NetworkMonitorCore

// MARK: - 删除二次确认与右键菜单指令（从面板控制器拆出，守住单文件体积上限）

/// 右键菜单指令 → 控制器既有动作；删除类操作一律先过二次确认
extension ClipboardPanelController {

    // MARK: 删除确认

    /// 请求删除选中条目：首次只提示确认，窗口内再次请求才真正删除
    func requestDeleteSelected() {
        guard let item = selectedItem else { return }
        guard requestSingleDeleteConfirm(for: item) else { return }
        ClipboardImageGC.delete(repository: repository, id: item.id, logger: logger)
        logger.info("剪贴板单条已删除（二次确认通过）")
        AppEvents.postClipboardChanged()
        reloadItems()
        content.showHint(ClipboardPanelView.keyHint)
    }

    /// 请求清空历史：与单条删除各持独立确认状态，互不串味
    func requestClearAll() {
        guard clearAllConfirm.requestDelete(id: Self.clearAllConfirmKey, now: Date().timeIntervalSince1970) else {
            let removed = ClipboardImageGC.clear(repository: repository, keepingPinned: true, logger: logger)
            logger.info("剪贴板历史已清空，删除 \(removed) 条（收藏保留）")
            AppEvents.postClipboardChanged()
            reloadItems()
            content.showHint("已清空历史（收藏项保留）")
            return
        }
        content.showHint("再按一次 ⌘⇧⌫ 清空历史（收藏项保留）")
    }

    /// 丢弃未完成的删除确认（菜单收起、面板收起、换了选中条目时调用）
    func discardDeleteConfirm() {
        singleDeleteConfirm.reset()
        clearAllConfirm.reset()
    }

    /// 选中条目变化 / 面板收起时清掉确认提示，避免提示指向另一条
    func clearDeleteConfirmHint() {
        guard singleDeleteConfirm.hasPending || clearAllConfirm.hasPending else { return }
        discardDeleteConfirm()
        content.showHint(ClipboardPanelView.keyHint)
    }

    /// 单条删除确认：首次返回 true（需确认并已给出提示），窗口内二次请求返回 false（可执行）
    private func requestSingleDeleteConfirm(for item: ClipboardItem) -> Bool {
        let needsConfirm = singleDeleteConfirm.requestDelete(id: item.id, now: Date().timeIntervalSince1970)
        if needsConfirm {
            logger.debug("剪贴板单条删除待确认（窗口内再次请求即执行）")
            content.showHint(ClipboardDeleteHint.single)
        }
        return needsConfirm
    }

    // MARK: 右键菜单指令

    /// 卡片右键菜单：复制 / 粘贴为纯文本 / 收藏 / 删除，全部复用本控制器既有动作
    ///
    /// 「贴到屏幕」不经此通道（卡片 onPin → 贴图链路），此处只处理其余四项。
    func panelView(_ view: ClipboardPanelView, didRequestMenuCommand command: ClipboardCardMenuCommand, itemID: UUID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == itemID }) else { return }
        if index != selectedIndex {
            selectedIndex = index
            content.updateSelection(index)
        }
        switch command {
        case .copy:
            copySelected()
        case .pastePlainText:
            pasteSelected(asPlainText: true)
        case .togglePin:
            togglePin()
        case .delete:
            requestDeleteSelected()
        case .pinToScreen:
            // 贴到屏幕由卡片 onPin 直接分发到贴图链路，菜单通道不再重复实现
            break
        }
    }

    /// 「清空历史」确认用的固定标识（仅作状态机标识，与条目 ID 语义无关）
    static let clearAllConfirmKey = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
}

// MARK: - 删除确认提示文案

/// 面板内删除确认文案（统一走提示行 showHint 通道，不弹独立窗口）
enum ClipboardDeleteHint {
    /// 单条删除的二次确认提示
    static let single = "再按一次 ⌫ 删除该条"
}