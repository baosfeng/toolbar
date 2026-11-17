import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - Token 页交互接线与一次性提示（TokenPaneView 扩展）

/// 从 TokenPaneView.swift 拆出（主文件已贴单单文件 15 KiB 上限）
///
/// 只放「控件事件接成什么行为」与「一次性提示怎么显示」：
/// 数据注入（update）与状态机在 +State.swift，布局在 +Layout.swift，渲染在 +Render.swift。
extension TokenPaneView {

    func wireActions() {
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        // 不可用态的动作行：三类失败都指向设置 →「Token 用量」（改目录 / 看 zstd 探测链）
        unavailableView.actionRow.onClick = { [weak self] in self?.onOpenSettings?(.token) }
        rangeControl.onSelect = { [weak self] index in
            guard let self, let value = TokenRange(rawValue: index) else { return }
            self.range = value
            self.render()
        }
        daySegment.onSelect = { [weak self] index in
            guard let self, let value = TokenHourScope(rawValue: index) else { return }
            self.hourScope = value
            self.render()
        }
        viewAction.onClick = { [weak self] in
            guard let self else { return }
            self.hourView = self.hourView == .stack ? .compare : .stack
            self.render()
        }
        hourAction.onClick = { [weak self] in
            guard let self else { return }
            self.metric = self.metric == .total ? .request : .total
            self.render()
        }
        trendAction.onClick = { [weak self] in
            guard let self else { return }
            self.trendMode = self.trendMode == .stack ? .line : .stack
            self.render()
        }
        for card in familyCards {
            card.onClick = { [weak self] in self?.openDetail(.hourly) }
        }
        hourCard.onClick = { [weak self] in self?.openDetail(.hourly) }
        hourBars.onSelect = { [weak self] index in
            guard let self else { return }
            self.openDetail(.bucket,
                            selection: TokenBucketSelection(index: index,
                                                           isHour: self.range == .today,
                                                           scope: self.hourScope))
        }
        trendCard.onClick = { [weak self] in self?.openDetail(.trend) }
        overviewTrendCard.onClick = { [weak self] in self?.openDetail(.trend) }
        screenControl.onSelect = { [weak self] index in
            guard let self, let value = TokenScreen(rawValue: index) else { return }
            self.selectScreen(value)
        }
        // 排行屏的维度分段与屏切换走同一条 render 路径（不各走一套刷新）
        rankScreen.onDimensionChange = { [weak self] in self?.render() }
        detailPane.onBack = { [weak self] in self?.closeDetail() }
        detailPane.onSelectBucket = { [weak self] selection in
            self?.openDetail(.bucket, selection: selection)
        }
    }

    // MARK: - 一键重扫

    /// 页头刷新：清空本机索引后全量重建，过程与回执都落在索引标签上
    ///
    /// 索引进行中点刷新不再被静默丢弃：服务侧把请求入队，本轮结束接着跑这一轮。
    func rebuildIndex() {
        guard let harness else { return }
        showIndexNote("正在清空索引并全量重建…", isWarning: false)
        harness.rebuildIndex(scope: .full) { [weak self] receipt in
            Task { @MainActor in
                guard let self else { return }
                // 索引结束后先清掉过程提示，再按回执重贴：否则过程文案会盖住最终结果
                self.durableNote = nil
                self.update(harness.snapshot())
                if let receipt {
                    self.showIndexNote(receipt.summaryText, isWarning: receipt.sessionsFailed > 0)
                } else {
                    self.showIndexNote("重建未执行：数据源不可用或清理失败", isWarning: true)
                }
            }
        }
    }

    // MARK: - 一次性提示

    /// 在索引标签上显示一条临时说明（重扫进度 / 回执 / 失败原因）；用现有标签承载，不新增视图。
    func showIndexNote(_ text: String, isWarning: Bool, autoClearSeconds: UInt64 = 8) {
        durableNote = (text, isWarning)
        applyDurableNote()
        noteExpiry?.cancel()
        noteExpiry = Task { [weak self] in
            try? await Task.sleep(nanoseconds: autoClearSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.clearIndexNote() }
        }
    }

    /// 清掉临时提示并回到常规显示（自动到期或下一轮状态刷新时调用）
    func clearIndexNote() {
        noteExpiry = nil
        durableNote = nil
        guard let snapshot else {
            indexLabel.isHidden = true
            return
        }
        update(snapshot)
    }

    /// 把常驻提示贴回索引标签（状态机重渲后会把它盖掉，所以每次重渲都要补一次）
    func applyDurableNote() {
        guard let durableNote else { return }
        indexLabel.stringValue = durableNote.text
        indexLabel.textColor = durableNote.isWarning ? TokenPaneStyle.warnInk : TokenPaneStyle.tertiaryText
        indexLabel.isHidden = false
    }

}