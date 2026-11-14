import AppKit

// MARK: - 面板根视图 · 键盘可达

/// 键盘可达：Esc / Tab / 方向键 / 数字键 / Enter，以及行与卡片共享的焦序遍历
///
/// 从 `MenuPanelView.swift` 拆出（主文件贴近单文件 15 KiB 上限）；
/// 成员跨文件访问，故 `moveFocus` / `setFocus` / `activateFocusedTarget` 放宽为 internal。
extension MenuPanelView {

    // MARK: - 键盘可达

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains(.command) {
            switch characters {
            case "q": delegate?.menuPanelViewDidRequestQuit(self)
            case ",": delegate?.menuPanelViewDidRequestSettings(self, section: nil)
            default: super.keyDown(with: event)
            }
            return
        }

        switch Int(event.keyCode) {
        case 53:  // Esc：二级页先返回主面板，否则收起面板
            if currentTab == .system, systemPane.isShowingDetail {
                systemPane.showOverview()
            } else if currentTab == .token, tokenPane.isShowingDetail {
                // Token 二级页原先没有 Esc 分支：按 Esc 直接把面板收起，
                // 再打开时 detailKind 已被 applyState 复位，页面上下文丢失
                tokenPane.closeDetail()
            } else {
                delegate?.menuPanelViewDidRequestClose(self)
            }
        case 48:  // Tab
            moveFocus(by: flags.contains(.shift) ? -1 : 1)
        case 126:  // ↑
            moveFocus(by: -1)
        case 125:  // ↓
            moveFocus(by: 1)
        case 123:  // ←
            switchTab(by: -1)
        case 124:  // →
            switchTab(by: 1)
        case 36, 49, 76:  // Return / Space / 小键盘 Enter
            activateFocusedTarget()
        default:
            if let number = Int(characters), number >= 1,
               number <= tabBar.visibleTabs.count {
                select(tab: tabBar.visibleTabs[number - 1])
                return
            }
            super.keyDown(with: event)
        }
    }

    /// 在可点击元素之间移动键盘焦点（行在前、卡片在后；循环）
    func moveFocus(by delta: Int) {
        let count = activePane.focusableRows.count + activePane.focusableCards.count
        guard count > 0 else { return }
        let next: Int
        if let current = focusedIndex {
            next = ((current + delta) % count + count) % count
        } else {
            next = delta >= 0 ? 0 : count - 1
        }
        setFocus(index: next)
    }

    /// 设置聚焦元素（nil 清除；行与卡片共享一条焦序遍历）
    func setFocus(index: Int?) {
        let rows = activePane.focusableRows
        let cards = activePane.focusableCards
        let count = rows.count + cards.count
        let validIndex = index.flatMap { (0..<count).contains($0) ? $0 : nil }
        for (rowIndex, row) in rows.enumerated() {
            row.setKeyboardFocused(rowIndex == validIndex)
        }
        for (cardIndex, card) in cards.enumerated() {
            card.setCardKeyboardFocused(rows.count + cardIndex == validIndex)
        }
        focusedIndex = validIndex
    }

    /// 触发当前聚焦元素（与点击同路径）
    func activateFocusedTarget() {
        guard let index = focusedIndex else { return }
        let rows = activePane.focusableRows
        let cards = activePane.focusableCards
        if rows.indices.contains(index) {
            rows[index].activate()
        } else if cards.indices.contains(index - rows.count) {
            cards[index - rows.count].activateCard()
        }
    }

    /// 把键盘焦点还给指定卡片（从系统页详情返回时）
    func focus(card: SystemCardView) {
        let rows = activePane.focusableRows
        guard let index = activePane.focusableCards.firstIndex(where: { $0 === card }) else {
            return
        }
        setFocus(index: rows.count + index)
    }
}
