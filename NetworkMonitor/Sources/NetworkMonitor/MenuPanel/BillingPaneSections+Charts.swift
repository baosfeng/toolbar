import AppKit
import NetworkMonitorCore

// MARK: - 展开区柱图数据（纯换算）

/// 柱图取值与悬停文案 —— 从 `BillingUsageSectionView` 拆出
///
/// 成员由 `private` 放宽为 `internal`：供同模块主文件调用。
extension BillingUsageSectionView {

    /// 单桶绘图值：有金额按金额、遗留计划按请求数（否则所有柱高为 0、图表不可读）
    static func barValue(_ bucket: BillingBucket, usesUSD: Bool) -> Double {
        usesUSD
            ? max(0, bucket.metrics.usageUSD ?? 0)
            : Double(max(0, bucket.metrics.requestCount))
    }

    /// 单桶悬停文案：`22:00–23:00 · $0.0088` / `22:00–23:00 · 2400 次`
    static func bucketCaption(_ bucket: BillingBucket, granularity: BillingGranularity,
                              usesUSD: Bool) -> String {
        let start = formatBucketLabel(bucket.start, granularity: granularity)
        let end = formatBucketLabel(bucket.end, granularity: granularity)
        let value = usesUSD
            ? formatUSD(barValue(bucket, usesUSD: true))
            : "\(Int(barValue(bucket, usesUSD: false))) 次"
        return "\(start)–\(end) · \(value)"
    }

    /// 轴左侧标签：首桶时间（M/d 或 HH:00）
    static func axisLeft(_ usage: BillingUsage) -> String {
        guard let first = usage.buckets.first else { return "" }
        return formatBucketLabel(first.start, granularity: usage.granularity)
    }
}
