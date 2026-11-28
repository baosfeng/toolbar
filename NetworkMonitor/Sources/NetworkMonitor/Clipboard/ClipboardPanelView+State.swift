import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 面板状态更新（从主文件拆出，守住 15 KiB 上限）
//
// 卡片流重排 / 选中态 / 计数 / 胶囊提示 / 筛选芯片 / 搜索串全在这一处；
// 主文件只留构建、布局与动作出口（query / filterTokens / selectedIndex 因此放宽为 internal）。

extension ClipboardPanelView {
    // MARK: 对外状态更新

    /// 重建卡片流：交给卡片流视图做「视图池复用 + 滑动窗口」，此处不建任何卡片
    func render(items: [ClipboardItem], selectedIndex: Int, selectedIDs: Set<UUID>? = nil) {
        self.selectedIndex = selectedIndex
        let ids = selectedIDs ?? ClipboardCardFlowView.singleSelection(items: items, index: selectedIndex)
        cardFlow.render(items: items, selectedIndex: selectedIndex, selectedIDs: ids)
        // 多选摘要改由底部状态胶囊承担（详情区已退成编辑浮层）
        statusBand.updateMultiSelection(count: ids.count)
    }

    /// 仅切换选中态（方向键移动时不重建卡片视图）
    func updateSelection(_ index: Int, item: ClipboardItem?, selectedIDs: Set<UUID>? = nil) {
        _ = item
        selectedIndex = index
        let ids = selectedIDs ?? ClipboardCardFlowView.singleSelection(items: cardFlow.items, index: index)
        cardFlow.updateSelection(index, selectedIDs: ids)
        statusBand.updateMultiSelection(count: ids.count)
    }

    /// 多选态：底部胶囊改成「已选 N 条」摘要（单条详情在空格预览里看）
    func updateMultiSelection(count: Int) {
        statusBand.updateMultiSelection(count: count)
    }

    /// 更新栈进度（如「堆叠 2 条」；栈空时收起，不占位）
    func updateStack(remaining: Int, total: Int) {
        _ = total
        stackRemaining = max(0, remaining)
        refreshCountsLabel()
    }

    /// 工具条计数：「N 条 · 收藏 M」＋ 栈剩余；胶囊只留给提示 / 暂停 / 多选 / 权限
    func refreshCountsLabel() {
        var text = ClipboardPanelFooterText.countsLabel(total: totalCount, pinned: pinnedCount)
        if stackRemaining > 0 { text += " · 栈 \(stackRemaining)" }
        countLabel.stringValue = text
        countLabel.setAccessibilityLabel(text)
        needsLayout = true
    }

    /// 更新辅助功能权限状态（无权限时高亮入口，不得静默）
    func updatePermission(accessibilityGranted: Bool) {
        statusBand.updatePermission(granted: accessibilityGranted)
    }

    /// 临时提示（降级路径必须让用户看见）：底部胶囊显示 4 秒后自动收起
    func showHint(_ text: String) {
        statusBand.showHint(text)
    }

    /// 透出暂停态：胶囊常驻「采集已暂停（点此恢复）」，定时暂停带出截止时刻
    func revealPauseState(_ isPaused: Bool, until pausedUntil: Date = .distantPast, now: Date = Date()) {
        let text = ClipboardPauseLogic.footerHint(isPaused: isPaused, pausedUntil: pausedUntil,
                                                  now: now, idleHint: Self.keyHint)
        statusBand.revealPause(isPaused, text: isPaused ? text : "")
        statusBand.setAccessibilityLabel(isPaused ? "采集已暂停，点按或按 ⌘P 恢复采集" : "面板状态")
    }

    /// 暂停胶囊的点击恢复
    @objc func resumeFromPauseBanner() { onRequestTogglePause?() }

    /// 替换全部筛选芯片（增删 / ⇧Tab 循环 / 清空都走这里）：视图只回传新数组，匹配交给控制器；
    /// 芯片宽度依赖字体，换完要重排工具条。
    func setFilterTokens(_ tokens: [ClipboardFilterToken]) {
        guard tokens != filterTokens else { return }
        filterTokens = tokens
        chipRowView.update(tokens: tokens)
        needsLayout = true
        delegate?.panelView(self, didChangeFilterTokens: tokens)
    }

    /// 让搜索框成为第一响应者（面板打开即可输入）
    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        // 高亮只跟搜索态走：查询清空后立即回落无高亮（不等下一次重排）
        cardFlow.setHighlightQuery(query)
        delegate?.panelView(self, didChangeQuery: query)
    }

    /// 外部（控制器 / 快照）改写搜索串：同步搜索框、卡片高亮与查询态
    func setQuery(_ text: String) {
        guard searchField.stringValue != text else { return }
        searchField.stringValue = text
        query = text
        cardFlow.setHighlightQuery(text)
        delegate?.panelView(self, didChangeQuery: text)
    }
}
