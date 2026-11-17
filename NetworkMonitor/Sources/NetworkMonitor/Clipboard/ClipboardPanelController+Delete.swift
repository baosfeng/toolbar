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
        guard ClipboardImageGC.delete(repository: repository, id: item.id, logger: logger) else {
            // 删除没命中（条目已被别的路径删掉）：给失败音，不谎报成功
            feedback.sound.play(.error)
            logger.warning("剪贴板单条删除失败：条目已不存在")
            AppEvents.postClipboardChanged()
            reloadItems()
            content.showHint("该条目已不存在")
            return
        }
        feedback.sound.play(.delete)
        logger.info("剪贴板单条已删除（二次确认通过）")
        AppEvents.postClipboardChanged()
        reloadItems()
        content.showHint(ClipboardPanelView.keyHint)
    }

    /// 请求清空历史：与单条删除各持独立确认状态，互不串味
    func requestClearAll() {
        guard clearAllConfirm.requestDelete(id: Self.clearAllConfirmKey, now: Date().timeIntervalSince1970) else {
            let removed = ClipboardImageGC.clear(repository: repository, keepingPinned: true, logger: logger)
            if removed == 0 {
                // 本来就没有可清空的内容：不打删除音，避免「点了没反应却有声音」的错觉
                logger.debug("剪贴板历史清空：没有可删除的条目（收藏保留）")
            } else {
                feedback.sound.play(.delete)
            }
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
        guard singleDeleteConfirm.hasPending || clearAllConfirm.hasPending
                || multiDeleteConfirm.hasPending else { return }
        discardDeleteConfirm()
        multiDeleteConfirm.reset()
        content.showHint(ClipboardPanelView.keyHint)
    }

    /// 丢弃未完成的删除确认（含批量删除那一份）
    func discardAllDeleteConfirm() {
        discardDeleteConfirm()
        multiDeleteConfirm.reset()
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

    /// 卡片右键菜单各项复用本控制器既有动作；「贴到屏幕」走卡片 onPin，不经此通道。
    func panelView(_ view: ClipboardPanelView, didRequestMenuCommand command: ClipboardCardMenuCommand, itemID: UUID) {
        guard let index = filteredItems.firstIndex(where: { $0.id == itemID }) else { return }
        // 右键某条即把它落成焦点单条：菜单动作永远只作用于一条
        if selection.focusedID != itemID || selection.isMultiSelecting { selectSingle(at: index) }
        switch command {
        case .copy:
            copySelected()
        case .copyOCRText:
            copyRecognizedText()
        case .pastePlainText:
            pasteSelected(asPlainText: true)
        case .edit: beginEditingSelected()   // 与 ⌘E 共用同一实现
        case .togglePin:
            togglePin()
        case .delete:
            requestDeleteSelected()
        case .pinToScreen:
            break   // 贴到屏幕由卡片 onPin 直接分发到贴图链路
        }
    }

    /// 「清空历史」确认用的固定标识（仅作状态机标识，与条目 ID 语义无关）
    static let clearAllConfirmKey = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
}

/// 面板内删除确认文案（统一走提示行 showHint 通道，不弹独立窗口）
enum ClipboardDeleteHint {
    /// 单条删除的二次确认提示
    static let single = "再按一次 ⌫ 删除该条"
}