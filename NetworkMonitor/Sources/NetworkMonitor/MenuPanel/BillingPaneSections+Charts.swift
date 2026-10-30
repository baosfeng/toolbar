import AppKit
import NetworkMonitorCore

// MARK: - 用量区（柱状图数据）

/// 柱状图数据换算与轴标签 — 从 `BillingUsageSectionView` 拆出（主文件超 15 KiB 上限）
///
/// 成员由 `private` 放宽为 `internal`：供同模块主文件调用。
extension BillingUsageSectionView {

    /// 分桶 → 柱体数据
    ///
    /// 度量自适应：优先按金额绘制；遗留计划只返回请求数（无 usage_usd）时改用请求数，
    /// 否则所有柱高为 0、数值全是 "$0.000"，图表不可读。
    /// 柱数较多时只给最大桶显示数值文案，避免 9pt 数值互相重叠。
    static func makeBars(_ usage: BillingUsage) -> [MenuPanelBarsView.Bar] {
        let buckets = usage.buckets
        let showEveryValue = buckets.count <= 6
        let usesUSD = buckets.contains { ($0.metrics.usageUSD ?? 0) > 0 }
        let values = buckets.map { bucket -> Double in
            usesUSD ? max(0, bucket.metrics.usageUSD ?? 0) : Double(max(0, bucket.metrics.requestCount))
        }
        let maxValue = values.max() ?? 0
        return buckets.enumerated().map { index, bucket in
            let value = values[index]
            let isLast = index == buckets.count - 1
            let showsValue = maxValue > 0 && (showEveryValue || value >= maxValue)
            let valueText: String
            if !showsValue {
                valueText = ""
            } else if usesUSD {
                valueText = formatUSD(value)
            } else {
                valueText = "\(Int(value)) 次"
            }
            let rawValue: UInt64 = usesUSD
                ? UInt64(min(value * 1_000_000, 1e15))
                : UInt64(min(value, 1e15))
            // 悬停提示：桶的时间范围 + 完整数值（不显示时也能看到这一小时/一天的数据）
            let startLabel = formatBucketLabel(bucket.start, granularity: usage.granularity)
            let endLabel = formatBucketLabel(bucket.end, granularity: usage.granularity)
            let detail = usesUSD
                ? "\(startLabel)–\(endLabel) · \(formatUSD(value))"
                : "\(startLabel)–\(endLabel) · \(Int(value)) 次"
            return MenuPanelBarsView.Bar(label: "",
                                         value: rawValue,
                                         valueText: valueText,
                                         isToday: isLast,
                                         detail: detail)
        }
    }

    /// 轴左侧标签：首桶时间（M/d 或 HH:00）
    static func axisLeft(_ usage: BillingUsage) -> String {
        guard let first = usage.buckets.first else { return "" }
        return formatBucketLabel(first.start, granularity: usage.granularity)
    }
}
