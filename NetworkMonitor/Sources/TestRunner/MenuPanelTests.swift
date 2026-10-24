import Foundation
import NetworkMonitorCore

// MARK: - 菜单面板取数口径（从 main.swift 拆出）

// MARK: - MenuPanelMetrics 菜单面板取数口径

func runMenuPanelMetricsTests() {
    print("\n🧪 Testing MenuPanelMetrics...")
    do {
        // 近 6 日柱状图：入参今天在最前（降序），出参改成时间正序且今天标尾
        let entries: [(label: String, rx: UInt64, tx: UInt64)] = [
            ("10/16", 5_600_000_000, 800_000_000),
            ("10/15", 2_000_000_000, 300_000_000),
            ("10/14", 1_800_000_000, 200_000_000),
        ]
        let six = MenuPanelMetrics.recentDays(entries: entries, limit: 6)
        assertEqual(six.count, 3, "不足 6 天时按实际条数返回")
        assertEqual(six.map(\.label), ["10/14", "10/15", "10/16"], "时间正序：最左最早、最右今天")
        assertEqual(six.last?.isToday, true, "最后一条标记为今天")
        assertEqual(six.first?.isToday, false, "历史条目不是今天")

        let capped = MenuPanelMetrics.recentDays(entries: entries, limit: 2)
        assertEqual(capped.map(\.label), ["10/15", "10/16"], "limit 取最近 N 天并保持正序")
        assertEqual(capped.last?.isToday, true, "截断后今天仍标记")
        assertEqual(MenuPanelMetrics.recentDays(entries: entries, limit: 0).count, 0, "limit=0 返回空")
        assertEqual(MenuPanelMetrics.recentDays(entries: entries, limit: -3).count, 0, "负 limit 返回空")
        assertEqual(MenuPanelMetrics.recentDays(entries: [], limit: 6).count, 0, "无数据返回空")

        // 今日流量占比：下行 /（下行 + 上行）
        assertEqual(MenuPanelMetrics.downShare(rx: 8_000, tx: 2_000), 0.8, "80% 下行占比")
        assertEqual(MenuPanelMetrics.downShare(rx: 1_000, tx: 0), 1.0, "只有下行时占比 1")
        assertEqual(MenuPanelMetrics.downShare(rx: 0, tx: 0), 0.0, "总量为 0 时占比 0")

        // 柱高比例：相对最大值；全 0 不产生 NaN
        assertEqual(MenuPanelMetrics.barRatios(values: [0, 50, 100]), [0, 0.5, 1], "相对最大值归一化")
        assertEqual(MenuPanelMetrics.barRatios(values: [0, 0]), [0, 0], "全 0 时高度全 0")
        assertEqual(MenuPanelMetrics.barRatios(values: []).isEmpty, true, "空数组返回空")

        // 速率拆分：数值段 + 单位段
        let zero = MenuPanelMetrics.speedParts(0)
        assertEqual(zero.value, "0", "0 速率数值段")
        assertEqual(zero.unit, "B/s", "0 速率单位段")
        let kilo = MenuPanelMetrics.speedParts(1_500)
        assertEqual(kilo.value, "2", "1.5K 数值段四舍五入")
        assertEqual(kilo.unit, "KB/s", "1.5K 单位段")
        let mega = MenuPanelMetrics.speedParts(1_200_000)
        assertEqual(mega.value, "1.2", "1.2M 数值段")
        assertEqual(mega.unit, "MB/s", "1.2M 单位段")
        let giga = MenuPanelMetrics.speedParts(2_300_000_000)
        assertEqual(giga.value, "2.3", "2.3G 数值段")
        assertEqual(giga.unit, "GB/s", "2.3G 单位段")
        let negative = MenuPanelMetrics.speedParts(-1_500_000)
        assertEqual(negative.value, "1.5", "负速率按绝对值展示")
        assertEqual(negative.unit, "MB/s", "负速率单位不变")

        // 活跃进程 Top N：零流量过滤 + 总量降序 + 上限截断
        let processes = [
            ProcessNetUsage(name: "Safari", pid: 1, bytesIn: 100, bytesOut: 100),
            ProcessNetUsage(name: "idle", pid: 2, bytesIn: 0, bytesOut: 0),
            ProcessNetUsage(name: "Chrome", pid: 3, bytesIn: 900, bytesOut: 100),
            ProcessNetUsage(name: "Slack", pid: 4, bytesIn: 50, bytesOut: 50),
        ]
        let topTwo = MenuPanelMetrics.topProcesses(processes, limit: 2)
        assertEqual(topTwo.map(\.name), ["Chrome", "Safari"], "按总流量降序取 Top2")
        assertEqual(MenuPanelMetrics.topProcesses(processes, limit: 10).count, 3, "零流量进程被过滤")
        assertEqual(MenuPanelMetrics.topProcesses(processes, limit: 0).isEmpty, true, "limit=0 返回空")

        print("✅ MenuPanelMetrics 面板取数口径 works")
    }

}

