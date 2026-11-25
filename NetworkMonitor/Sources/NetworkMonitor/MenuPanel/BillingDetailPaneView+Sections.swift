import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 二级页的数据与两块卡片（与主文件按职责分开）

/// BillingDetailPaneView 的数据更新 —— 从主文件拆出（主文件只留装配与导航）
///
/// 这里放「一帧状态怎么落到窗口大卡 / 余额卡 / 柱图 / 模型明细」，
/// 主文件只管容器、返回按钮与互斥显隐（单文件 15 KiB 门禁）。
extension BillingDetailPaneView {

    // MARK: - 数据

    /// 应用某一家 provider
    ///
    /// - Parameters:
    ///   - state: 该 provider 的运行时状态
    ///   - columnCount: 主表当前列数（余额型仍按主表列数排，避免金额行突然变宽）
    func update(state: BillingMonitor.ProviderState, columnCount: Int) {
        providerID = state.descriptor.id
        titleLabel.stringValue = state.descriptor.displayName
        metaLabel.stringValue = Self.metaText(state)
        setAccessibilityLabel("额度二级详情页 " + state.descriptor.displayName)

        let windows = BillingProviderTableView.tableRow(state).windows
        let showsWindows = !windows.isEmpty
        windowCard.isHidden = !showsWindows
        balanceCard.isHidden = showsWindows || state.balance == nil
        // 只画这一家：列数取它自己的窗口数（沿用主表列数会留一排空格）
        let count = min(max(windows.count, 1), windowColumns.count)
        let padded = BillingAggregate.padded(
            BillingAggregate.ProviderRow(id: state.descriptor.id,
                                         name: state.descriptor.displayName,
                                         windows: windows,
                                         isBalanceOnly: !showsWindows),
            columnCount: count)
        for (index, column) in windowColumns.enumerated() {
            guard index < padded.count, let spec = padded[index] else {
                column.isHidden = true
                column.clear()
                continue
            }
            column.isHidden = false
            column.isCompact = false
            column.update(BillingWindowColumnView.Spec(title: spec.title,
                                                       remaining: spec.remaining,
                                                       resetsAt: spec.resetsAt,
                                                       badge: spec.badge))
        }
        applyBalance(state)
        applyUsage(state, showsWindows: showsWindows)

        let showsError = state.errorMessage != nil
        errorBanner.isHidden = !showsError
        if let message = state.errorMessage { errorBanner.update(message: message) }

        hintLabel.stringValue = showsWindows
            ? "返回额度主表 · 单家完整用量不占主表空间"
            : "纯余额型 · 只出余额与用尽提醒，没有窗口百分比"
        hintLabel.isHidden = false
    }

    /// 用量两块（柱图 + 模型）
    private func applyUsage(_ state: BillingMonitor.ProviderState, showsWindows: Bool) {
        guard let usage = state.usage else {
            chartCard.isHidden = true
            modelCard.isHidden = true
            return
        }
        chartTitle.stringValue = showsWindows ? "近 7 天用量" : "近 7 天花费"
        let series = BillingChartAggregate.chart(usages: [usage], range: .last7Days)
        chartCard.isHidden = series.isEmpty
        if !series.isEmpty {
            chartMeta.stringValue = BillingChartAggregate.chartSubtitle(series, range: .last7Days)
            barsView.update(points: series.points, metric: series.metric, granularity: .day,
                            fillColor: BillingChartsSectionView.barColor(series.metric))
        }
        let models = BillingChartAggregate.topModels(usages: [usage], range: .last7Days, limit: 4)
        modelList.update(models: models)
        modelCard.isHidden = models.isEmpty
    }

    /// 余额型：大字金额 + 币种 + 一行说明
    private func applyBalance(_ state: BillingMonitor.ProviderState) {
        guard let balance = state.balance else {
            balanceLabel.stringValue = billingUnavailablePlaceholder
            balanceUnit.stringValue = ""
            balanceNote.stringValue = ""
            return
        }
        let total = balance.totalAvailableUSD
        let split = PaneValueFormatting.split(total.map { formatExactNumber($0) }
            ?? billingUnavailablePlaceholder)
        balanceLabel.stringValue = split.number
        balanceUnit.stringValue = total == nil ? "" : balance.currencyCode
        if total == nil {
            balanceNote.stringValue = "无限制 Key（没有可读的余额上限）"
        } else if let included = balance.included {
            balanceNote.stringValue = "内含剩余 "
                + formatCurrencyAmount(included.remainingUSD, code: balance.currencyCode)
                + " · 币种 " + balance.currencyCode
        } else {
            balanceNote.stringValue = "币种 " + balance.currencyCode + " · 按量后付费"
        }
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：强制悬停某根柱
    func forceHoverForSnapshot(_ index: Int?) {
        barsView.forceHoverForSnapshot(index)
    }
#endif

    /// 右侧口径：最近刷新时间（成功过给时分，否则说明为什么没有）
    static func metaText(_ state: BillingMonitor.ProviderState) -> String {
        if let updated = state.lastUpdated { return BillingTimeFormat.string(updated) }
        if state.isLoading { return "查询中" }
        return "未刷新"
    }
}
