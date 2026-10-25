import AppKit
import NetworkMonitorCore

// MARK: - 额度格与摘要行

/// 额度块的行内容装配 — 从 `BillingProviderBlockView.swift` 拆出
/// （主文件改造后已接近单文件 15 KiB 规范上限）
///
/// 行视图改为 internal 而非 private 是跨文件扩展的必然结果：它们只在 `MenuPanel` 目录内使用，
/// 不对外暴露。本文件负责「按限额数量排 1–3 列」与「收起态摘要行」两块纯装配逻辑。
extension BillingProviderBlockView {

    /// 按百分比限额数量动态排 1–3 列
    ///
    /// 无百分比限额时沿用旧兜底：只有金额型余额才显示「可用金额」，否则显示占位。
    func applyLimits(_ balance: BillingBalance?) {
        let limits = Array((balance?.percentLimits ?? []).prefix(Self.maxLimitColumns))
        if !limits.isEmpty {
            updateLimitCells(limits)
            return
        }
        if let total = balance?.totalAvailableUSD {
            limitCells[0].update(amount: formatUSD(total), title: "可用")
        } else {
            limitCells[0].clear()
        }
        revealLimitCells(1)
    }

    /// 逐格就地更新 —— 切换 provider 状态时复用已建好的 cell，不重建视图树
    private func updateLimitCells(_ limits: [BillingPercentLimit]) {
        // 三列时每列约 86pt：角标与重置时间同行会截断，改由 cell 内部上下两行排
        let isCompact = BillingLimitLayout.isCompact(columnCount: limits.count)
        for (index, cell) in limitCells.enumerated() where index < limits.count {
            cell.update(limit: limits[index], compact: isCompact)
        }
        revealLimitCells(limits.count)
    }

    /// 只显示前 count 格：隐藏的排列视图不参与 `fillEqually` 均分，单格时自动占满整行
    private func revealLimitCells(_ count: Int) {
        for (index, cell) in limitCells.enumerated() {
            cell.isHidden = index >= count
        }
    }

    /// 摘要行：有分桶能力时画迷你趋势，右侧给请求数与 token 汇总
    func applySummary(_ state: BillingMonitor.ProviderState) {
        let descriptor = state.descriptor
        let usage = state.usage
        let values: [Double]
        if descriptor.supportsTimeSeries, let usage {
            values = usage.buckets.map { Double($0.metrics.requestCount) }
        } else {
            values = []
        }
        if values.count >= 2 {
            trendView.update(values: values)
            trendView.isHidden = false
        } else {
            trendView.isHidden = true
        }

        var parts: [String] = []
        if let totals = usage?.totals {
            parts.append("\(totals.requestCount) 次")
            if let input = totals.inputTokens {
                parts.append("入 \(formatTokenCount(input))")
            }
        } else {
            parts.append(state.isLoading ? "查询中…" : "暂无用量")
        }
        summaryLabel.stringValue = parts.joined(separator: " · ")
    }
}