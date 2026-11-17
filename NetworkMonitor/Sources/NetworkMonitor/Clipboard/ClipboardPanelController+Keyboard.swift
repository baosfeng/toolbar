import AppKit
import Carbon
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板按键拦截（从面板控制器拆出，给操作反馈接线腾出主文件空间）

/// 面板级按键：先于 responder chain 拿到事件，再映射到控制器既有方法
///
/// 拆出原因：主文件贴着单文件 15 KiB 上限，按键映射自成体系；方法由 private 放宽为 internal。
extension ClipboardPanelController {

    /// 面板级按键拦截（先于 responder chain）：搜索框非空时 ⌫ 交还字段编辑器
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // 帮助浮层 / 预览浮层打开时 Esc 优先收起浮层（不连带着把面板一起关掉）
        if Int(event.keyCode) == kVK_Escape, dismissTopOverlay() { return true }
        // 编辑态：键盘属于编辑器，这里只留 Esc（取消）与 ⌘↩（保存），其余放行
        if content.isEditingBody { return handleEditingKeyDown(event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommand = flags.contains(.command), isShift = flags.contains(.shift)
        let isOption = flags.contains(.option), hasQuery = !content.query.isEmpty
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(animated: true)
        case kVK_Delete, kVK_ForwardDelete:
            if hasQuery { return false }
            if isCommand, isShift { requestClearAll() } else if !isCommand { requestDeleteSelected() } else { return false }
        case kVK_Tab:
            cycleFilter(reverse: isShift)   // ⇧Tab 反向循环过滤
        case kVK_ANSI_Comma:
            guard isCommand else { return false }
            hide(animated: false)
            onRequestSettings?()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            isCommand ? copySelected() : pasteSelected(asPlainText: isOption)
        case kVK_Space where content.query.isEmpty: togglePreview()   // 搜索态让位：空格仍是输入字符
        // ⌘← / ⌘→ 在板之间切换；不带 ⌘ 的 ←/→ 仍是条目前后移动
        case kVK_LeftArrow: isCommand ? boards.cycle(-1) : moveSelection(-1)
        case kVK_RightArrow: isCommand ? boards.cycle(1) : moveSelection(1)
        case kVK_UpArrow: moveSelection(-1)
        case kVK_DownArrow: moveSelection(1)
        default:
            guard isCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch characters {
            case "f": content.focusSearchField()
            case "e": beginEditingSelected()
            case "n": beginDraftingNewItem()
            case "d": togglePin()
            case "p": togglePause()   // 暂停 / 恢复采集（键位帮助浮层与提示行同口径）
            case "s": isShift ? clearStack() : pushSelectedToStack()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9": quickPaste(Int(characters) ?? 0)
            default: return false
            }
        }
        return true
    }

    /// 方向键移动：单行卡片流上连续前后移动；无选中时向前落第一条、向后落最后一条
    func moveSelection(_ delta: Int) {
        guard !filteredItems.isEmpty else { return }
        let base = selectedIndex < 0 ? (delta > 0 ? -1 : 0) : selectedIndex
        var next = base + delta
        if next < 0 { next = filteredItems.count - 1 }
        if next >= filteredItems.count { next = 0 }
        selectedIndex = next
        content.updateSelection(next, item: selectedItem)
        clearDeleteConfirmHint()
    }

    /// 类型芯片循环：Tab 正向 / ⇧Tab 反向（口径见 ClipboardFilterCycle，来源 / 日期芯片不动）
    func cycleFilter(reverse: Bool) {
        content.setFilterTokens(ClipboardFilterCycle.next(after: content.filterTokens, reverse: reverse))
    }

    /// ⌘1–⌘9 直选并粘贴（快速粘贴开关关闭时给出文案，不静默）
    func quickPaste(_ number: Int) {
        guard preferences.quickPasteEnabled else {
            content.showHint("快速粘贴已关闭（可在剪贴板设置中开启）")
            return
        }
        let index = number - 1
        guard index >= 0, index < filteredItems.count else { return }
        selectedIndex = index
        content.updateSelection(index, item: selectedItem)
        pasteSelected(asPlainText: false)
    }
}
