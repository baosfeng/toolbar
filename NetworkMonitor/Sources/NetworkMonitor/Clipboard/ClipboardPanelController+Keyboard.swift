import AppKit
import Carbon
import NetworkMonitorCore

// MARK: - 面板按键拦截（从面板控制器拆出，给操作反馈接线腾出主文件空间）

/// 面板级按键：先于 responder chain 拿到事件，再把动作映射到控制器既有方法
///
/// 拆出原因：主文件已贴着单文件 15 KiB 上限，接入音效 / 触觉后还要再加参数与属性，
/// 而按键映射本身是一段自成体系的纯分发逻辑，独立成文件更清晰。
/// 跨文件访问：`handleKeyDown` / `moveSelection` / `cycleFilter` / `quickPaste`
/// 由 private 放宽为 internal，仅供本扩展与主文件的回调闭包使用。
extension ClipboardPanelController {

    /// 面板级按键拦截（先于 responder chain）：搜索框非空时 ⌫ 交还字段编辑器
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // 帮助浮层打开时 Esc 优先收起浮层（不连带着把面板一起关掉）
        if Int(event.keyCode) == kVK_Escape, content.hideShortcutHelp() { return true }
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
        // 单行横向流：←/→ 连续前后移动，↑/↓ 等价映射为前后
        case kVK_LeftArrow: moveSelection(-1)
        case kVK_RightArrow: moveSelection(1)
        case kVK_UpArrow: moveSelection(-1)
        case kVK_DownArrow: moveSelection(1)
        default:
            guard isCommand, let characters = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch characters {
            case "d": togglePin()
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
        content.updateSelection(next)
        clearDeleteConfirmHint()
    }

    /// 过滤循环：⇧Tab 反向
    func cycleFilter(reverse: Bool) {
        let all = ClipboardFilter.allCases
        let step = reverse ? all.count - 1 : 1
        content.selectFilter(all[(content.filter.rawValue + step) % all.count])
        applyFilter(preferredID: selectedItem?.id)
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
        content.updateSelection(index)
        pasteSelected(asPlainText: false)
    }
}
