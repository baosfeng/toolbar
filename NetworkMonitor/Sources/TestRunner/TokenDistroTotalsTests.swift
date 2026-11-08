import Foundation
import NetworkMonitorCore

// MARK: - 排行屏汇总块的数据源（从 TokenPresentationTests 拆出：那边贴近 15 KiB 上限）

/// 汇总块取「该维度合计」，与占比分母是同一份数据（不是 TopN 行求和）。
/// 行会被截断，求和会让汇总块与每行占比对不上，所以这里锁死取的是 window totals。
private func testDistroTotals() {
    let projects = [
        HarnessProjectUsage(path: "/tmp/a", displayName: "a", sessionCount: 3,
                            usage: HarnessTokenUsage(uncachedInput: 100, output: 10,
                                                     cacheRead: 300, requestCount: 7)),
        HarnessProjectUsage(path: "/tmp/b", displayName: "b", sessionCount: 1,
                            usage: HarnessTokenUsage(uncachedInput: 50, output: 5,
                                                     cacheRead: 150, requestCount: 3)),
    ]
    let model = TokenPaneModel.make(snapshot: tokenSnapshot(projects: projects), range: .today,
                                    hourScope: .today, hourView: .stack,
                                    metric: .total, trendMode: .stack)
    assertEqual(model.projectTotals.totalTokens, 615, "汇总块总 tok = 该窗口全部项目合计")
    assertEqual(model.projectTotals.cacheRead, 450, "汇总块缓存读")
    assertEqual(model.projectTotals.uncached, 150, "汇总块未缓存输入")
    assertEqual(model.projectTotals.output, 15, "汇总块输出")
    assertEqual(model.projectTotals.requestCount, 10, "汇总块请求数")
    assertEqual(model.modelTotals.totalTokens, 0, "没有模型的窗口给 0，不编数")
    // 与占比分母同源：每行 share × 合计 应能还原出该行 tok
    let sum = model.projects.reduce(0) { $0 + (Int(Double(615) * $1.share)) }
    assertEqual(sum, 615, "合计与每行占比互相对得上（同一分母）")
    print("✅ 排行屏汇总块取该维度合计 works")
}

func runTokenDistroTotalsTests() {
    print("\n🧪 Testing 排行屏汇总块（维度合计 / 与占比分母同源）...")
    testDistroTotals()
    print("✅ 排行屏汇总块 works")
}
