import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度页总表口径

/// 断言 BillingAggregate 的三条页级判据：
/// 窗口列合并（列数 / 补齐 / 封顶）、限流计数、行构造（谁进上段谁走余额行）。
///
/// 图表口径（跨 provider 加总 / Top N / 空数据）在 BillingChartAggregateTests。
func runBillingAggregateTests() {
    print("\n🧪 Testing BillingAggregate...")

    windowColumnTests()
    throttledCountTests()
    rowBuilderTests()

    print("✅ BillingAggregate works")
}

// MARK: - 窗口列合并

private func windowColumnTests() {
    let twoWindows = BillingAggregate.ProviderRow(
        id: "ollama", name: "Ollama",
        windows: [column("会话", 0.68), column("每周", 0.04)],
        isBalanceOnly: false)
    let threeWindows = BillingAggregate.ProviderRow(
        id: "opencode-go", name: "OpenCode Go",
        windows: [column("5 小时", 0.62), column("每周", 0.48), column("每月", 0)],
        isBalanceOnly: false)
    let balanceOnly = BillingAggregate.ProviderRow(id: "deepseek", name: "DeepSeek",
                                                  windows: [], isBalanceOnly: true)

    // 1. 列数取各家最大值（封顶 3）：全表列宽必须统一，否则末行两列会撑宽整表
    assertEqual(BillingAggregate.columnCount([twoWindows, threeWindows, balanceOnly]), 3,
                "三窗口 provider 定下 3 列")
    assertEqual(BillingAggregate.columnCount([twoWindows, balanceOnly]), 2, "只有两窗口时是 2 列")
    assertEqual(BillingAggregate.columnCount([balanceOnly]), 0, "全余额型时没有窗口列")
    assertEqual(BillingAggregate.columnCount([]), 0, "空表 0 列")

    // 2. 四窗口也封顶 3（再宽会把百分比挤断）
    let fourWindows = BillingAggregate.ProviderRow(
        id: "x", name: "X",
        windows: [column("a", 0.9), column("b", 0.8), column("c", 0.7), column("d", 0.6)],
        isBalanceOnly: false)
    assertEqual(BillingAggregate.columnCount([fourWindows]), BillingAggregate.maxColumns,
                "四窗口封顶到 maxColumns")

    // 3. 补齐到全表列数：不足的列是 nil（占宽度、不画内容）
    let padded = BillingAggregate.padded(twoWindows, columnCount: 3)
    assertEqual(padded.count, 3, "补到 3 列")
    assertEqual(padded[0]?.title, "会话", "第一列原样")
    assertEqual(padded[1]?.title, "每周", "第二列原样")
    assertEqual(padded[2] == nil, true, "多出来的一列是空位")
    assertEqual(BillingAggregate.padded(twoWindows, columnCount: 0).count, 0, "0 列时返回空数组")
}

// MARK: - 限流计数

private func throttledCountTests() {
    let lowWindow = BillingAggregate.ProviderRow(
        id: "a", name: "A",
        windows: [column("会话", 0.68), column("每周", 0.04)],
        isBalanceOnly: false)
    let badgeWindow = BillingAggregate.ProviderRow(
        id: "b", name: "B",
        windows: [BillingAggregate.WindowColumn(title: "周", remaining: 0.9,
                                                resetsAt: nil, badge: "已限流")],
        isBalanceOnly: false)
    let healthy = BillingAggregate.ProviderRow(
        id: "c", name: "C",
        windows: [column("会话", 0.9), column("每周", 0.8)],
        isBalanceOnly: false)
    let balanceOnly = BillingAggregate.ProviderRow(id: "d", name: "D",
                                                  windows: [], isBalanceOnly: true)

    // 低于告警阈值与带角标都算限流；同一家只算一次；余额型不参与
    assertEqual(BillingAggregate.throttledCount([lowWindow, badgeWindow, healthy, balanceOnly]), 2,
                "4% 与角标各算一家，健康与余额型不算")
    assertEqual(BillingAggregate.throttledCount([healthy]), 0, "全健康时 0 家")
    assertEqual(BillingAggregate.throttledCount([]), 0, "空表 0 家")

    // 阈值边界：恰 20% 不算限流（判据与状态胶囊同源，用严格小于）
    let edge = BillingAggregate.ProviderRow(
        id: "e", name: "E",
        windows: [column("会话", BillingAggregate.warnThreshold)],
        isBalanceOnly: false)
    assertEqual(BillingAggregate.throttledCount([edge]), 0, "恰在阈值上不算限流")
}

// MARK: - 行构造

private func rowBuilderTests() {
    let rows = BillingAggregate.rows(entries: [
        (id: "ollama", name: "Ollama", subtitle: nil,
         windows: [column("会话", 0.9), column("每周", 0.4)]),
        (id: "deepseek", name: "DeepSeek", subtitle: nil, windows: []),
    ])
    assertEqual(rows.count, 2, "两家各一行")
    assertEqual(rows[0].isBalanceOnly, false, "有窗口的是用量型")
    assertEqual(rows[1].isBalanceOnly, true, "没窗口的是余额型")
    assertEqual(rows[0].id, "ollama", "顺序保持输入顺序（= provider 注册顺序）")

    // 超过 3 个窗口时只留前 3 列（与 columnCount 封顶一致）
    let many = BillingAggregate.rows(entries: [
        (id: "x", name: "X", subtitle: nil,
         windows: [column("a", 0.9), column("b", 0.8), column("c", 0.7), column("d", 0.6)]),
    ])
    assertEqual(many[0].windows.count, BillingAggregate.maxColumns, "行内窗口也封顶 3 列")
}

private func column(_ title: String, _ remaining: Double) -> BillingAggregate.WindowColumn {
    BillingAggregate.WindowColumn(title: title, remaining: remaining, resetsAt: nil)
}
