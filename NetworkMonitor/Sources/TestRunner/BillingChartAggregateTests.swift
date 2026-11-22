import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度页图表口径

/// 图表口径的断言 —— Top N 排序（同名累加 / 权重分档 / 其他合并行）与空数据判定
///
/// 从 BillingAggregateTests 拆出（单文件 15 KiB 门禁）：总表口径与图表口径
/// 是两个概念，测试文件也分开。
func runBillingChartAggregateTests() {
  print("\n🧪 Testing BillingChartAggregate...")
  topModelTests()
  aggregateEmptyTests()
  print("✅ BillingChartAggregate works")
}

private func usage(range: BillingRange, granularity: BillingGranularity, start: Date,
                   buckets: [BillingBucket]) -> BillingUsage {
    let end = buckets.last?.end ?? start
    let total = buckets.reduce(0) { $0 + $1.metrics.requestCount }
    let spend = buckets.reduce(0.0) { $0 + ($1.metrics.usageUSD ?? 0) }
    return BillingUsage(range: range, granularity: granularity, start: start, end: end,
                        totals: BillingMetrics(requestCount: total,
                                               usageUSD: spend > 0 ? spend : nil),
                        buckets: buckets)
}

private func bucket(_ start: Date, requests: Int, usd: Double? = nil) -> BillingBucket {
    BillingBucket(start: start, end: start.addingTimeInterval(86_400), isPartial: false,
                  metrics: BillingMetrics(requestCount: requests, usageUSD: usd))
}

// MARK: - Top N 排序

private func topModelTests() {
  let today = Calendar.current.startOfDay(for: Date())
  // 两家各报同名模型：必须累加，而不是出现两行同名
  let a = BillingUsage(range: .last7Days, granularity: .day, start: today, end: today,
             totals: BillingMetrics(), buckets: [],
             groups: [BillingGroup(name: "deepseek-chat",
                        metrics: BillingMetrics(requestCount: 100,
                                    inputTokens: 1_000)),
                 BillingGroup(name: "kimi-k2",
                        metrics: BillingMetrics(requestCount: 50,
                                    inputTokens: 500))])
  let b = BillingUsage(range: .last7Days, granularity: .day, start: today, end: today,
             totals: BillingMetrics(), buckets: [],
             groups: [BillingGroup(name: "deepseek-chat",
                        metrics: BillingMetrics(requestCount: 100,
                                    inputTokens: 1_000))])
  let models = BillingChartAggregate.topModels(usages: [a, b], range: .last7Days)
  assertEqual(models.count, 2, "同名模型合并成一行")
  assertEqual(models[0].name, "deepseek-chat", "权重大的排第一")
  assertEqual(models[0].share, 0.8, "占比 = 2000 / 2500")
  assertEqual(models[1].name, "kimi-k2", "第二名")
  assertEqual(models[1].share, 0.2, "占比 = 500 / 2500")

  // Top N 与「其他」合并行：分母仍是全部模型
  let many = BillingUsage(range: .last7Days, granularity: .day, start: today, end: today,
              totals: BillingMetrics(), buckets: [],
              groups: [BillingGroup(name: "m1", metrics: BillingMetrics(requestCount: 40)),
                   BillingGroup(name: "m2", metrics: BillingMetrics(requestCount: 30)),
                   BillingGroup(name: "m3", metrics: BillingMetrics(requestCount: 20)),
                   BillingGroup(name: "m4", metrics: BillingMetrics(requestCount: 6)),
                   BillingGroup(name: "m5", metrics: BillingMetrics(requestCount: 4))])
  let top4 = BillingChartAggregate.topModels(usages: [many], range: .last7Days, limit: 4)
  assertEqual(top4.count, 5, "Top 4 + 一行其他")
  assertEqual(top4.last?.isOther, true, "最后一行是其他合并行")
  assertEqual(top4.last?.name, "其他 1 个模型", "剩一个模型时写「其他 1 个模型」")
  assertEqual(top4.last?.share, 0.04, "其他行占比 4 / 100")
  let shares = top4.reduce(0.0) { $0 + $1.share }
  assertEqual(shares, 1.0, "各行占比之和为 1（分母是全部模型）")

  // 范围过滤与空数据
  assertEqual(BillingChartAggregate.topModels(usages: [a], range: .last30Days).count, 0,
        "范围不匹配时不返回任何模型")
  assertEqual(BillingChartAggregate.topModels(usages: [], range: .last7Days).count, 0,
        "没有用量时返回空数组")

  // 权重分档：有花费按花费排，没有花费按 token，再没有按请求数
  let weighted = BillingUsage(range: .last7Days, granularity: .day, start: today, end: today,
                totals: BillingMetrics(), buckets: [],
                groups: [BillingGroup(name: "cheap",
                           metrics: BillingMetrics(requestCount: 9_999,
                                       usageUSD: 0.01)),
                     BillingGroup(name: "pricey",
                           metrics: BillingMetrics(requestCount: 1,
                                       usageUSD: 0.9))])
  let bySpend = BillingChartAggregate.topModels(usages: [weighted], range: .last7Days)
  assertEqual(bySpend.first?.name, "pricey", "有花费时按金额排序，不是按请求数")
  assertContains(bySpend.first?.valueLabel ?? "", "$", "有金额时数值列显示金额")
}

// MARK: - 空数据

private func aggregateEmptyTests() {
  // 一条数据都没有：points 为空且 isEmpty（视图据此画空态，而不是画一排 0 高的柱）
  let empty = BillingChartAggregate.chart(usages: [], range: .last7Days)
  assertEqual(empty.points.isEmpty, true, "空输入没有柱")
  assertEqual(empty.isEmpty, true, "空序列 isEmpty")
  assertEqual(empty.total, 0, "空序列合计为 0")

  // 有桶但全为 0：同样是空态（不能显示一排空轨道假装有数据）
  let today = Calendar.current.startOfDay(for: Date())
  let zeros = usage(range: .last7Days, granularity: .day, start: today,
           buckets: [bucket(today, requests: 0)])
  let zeroSeries = BillingChartAggregate.chart(usages: [zeros], range: .last7Days)
  assertEqual(zeroSeries.peak, 0, "全零时峰值为 0")
  assertEqual(zeroSeries.isEmpty, true, "全零序列按空态处理")

  // 目标粒度与柱数上限（页面三段口径的唯一真源）
  assertEqual(BillingChartAggregate.granularity(for: .last24Hours), .hour, "24h 按小时")
  assertEqual(BillingChartAggregate.granularity(for: .last7Days), .day, "7d 按天")
  assertEqual(BillingChartAggregate.granularity(for: .last30Days), .day, "30d 按天")
  assertEqual(BillingChartAggregate.maxBuckets(for: .last24Hours), 8, "24h 8 根")
  assertEqual(BillingChartAggregate.maxBuckets(for: .last7Days), 7, "7d 7 根")
  assertEqual(BillingChartAggregate.maxBuckets(for: .last30Days), 10, "30d 10 根")
}
