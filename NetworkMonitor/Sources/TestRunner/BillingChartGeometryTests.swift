import CoreGraphics
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度柱图几何与范围对齐

/// 柱图几何 + 首帧范围对齐的断言
///
/// 这两块都是「读数口径」，改造前埋在可执行 target 的视图里，一条都断言不了：
/// 30d 柱宽被均分到 1pt、7d 悬停恒写「时」、首帧 provider range 与页级 range 不一致
/// 导致空图，全靠肉眼发现。抽到 NetworkMonitorUI 后在这里逐条锁住。
func runBillingChartGeometryTests() {
    print("\n🧪 Testing BillingChartGeometry...")
    columnGeometryTests()
    captionAndTickTests()
    rangeAlignmentTests()
    print("✅ BillingChartGeometry works")
}

// MARK: - 柱矩形

private func columnGeometryTests() {
    let plot = CGRect(x: 28, y: 0, width: 260, height: 76)
    let week = (1...7).map {
        BillingChartAggregate.ChartPoint(label: String(format: "%02d", $0),
                                        value: Double($0 * 100),
                                        isCurrent: $0 == 7)
    }

    // 7 根在 260pt 里：均分柱宽 34.9pt，被上限卡住 → 柱宽 = 上限、整体居中
    let columns = BillingChartGeometry.columns(week, in: plot)
    assertEqual(columns.count, 7, "7 个点出 7 根柱")
    assertEqual(columns.first?.frame.width ?? 0, BillingChartGeometry.maxBarWidth,
                "柱宽被上限卡住（改造前是全宽均分的胖柱）")
    let totalWidth = BillingChartGeometry.maxBarWidth * 7 + BillingChartGeometry.gap * 6
    assertEqual(columns.first?.frame.minX ?? 0, plot.minX + (plot.width - totalWidth) / 2,
                "柱宽封顶后整体居中（左侧留白 = 右侧留白）")
    assertEqual(columns.last?.frame.maxX ?? 0,
                plot.minX + (plot.width + totalWidth) / 2, "末柱右缘与左留白对称")

    // 自基线向上长：越高越靠上（flipped 里 y 小），最低值也至少 2pt
    let tallest = columns.last!.bar
    let shortest = columns.first!.bar
    assertEqual(tallest.maxY, plot.maxY, "柱底贴基线")
    assertEqual(shortest.maxY, plot.maxY, "矮柱底也贴基线（不是悬空的轨道）")
    assertEqual(tallest.height, plot.height, "峰值柱占满柱区高度")
    // 浮点归一：100 / 700 的比值乘回去有末位误差，按 0.001pt 容差比
    assertEqual(abs(shortest.height - plot.height * 100 / 700) < 0.001, true,
                "柱高按峰值归一（100 / 700 × 76pt）")

    // 值很小但不为零 → 最小柱高 2pt，否则读作「这段没有用量」
    let tiny = [BillingChartAggregate.ChartPoint(label: "01", value: 1, isCurrent: false),
                BillingChartAggregate.ChartPoint(label: "02", value: 100_000, isCurrent: true)]
    let tinyColumns = BillingChartGeometry.columns(tiny, in: plot)
    assertEqual(tinyColumns.first?.bar.height ?? 0, BillingChartGeometry.minBarHeight,
                "极小值仍画 2pt 最小柱高")

    // 值为 0 不画柱（高度 0），但命中区仍占位
    let zeros = [BillingChartAggregate.ChartPoint(label: "01", value: 0, isCurrent: false)]
    let zeroColumns = BillingChartGeometry.columns(zeros, in: plot)
    assertEqual(zeroColumns.first?.bar.height ?? -1, 0, "0 值柱高为 0（不画）")
    assertEqual(zeroColumns.first?.frame.height ?? 0, plot.height, "命中区仍占满柱区")

    // 30d 10 根：可用宽 242 / 10 = 24.2，未到 32pt 上限 → 仍按宽度均分；
    // 上限只在 24h 8 根 / 7d 7 根这种根数少的档生效（柱太胖正是「丑」的一半原因，
    // 另一半是柱区只有约 40pt 高）
    let month = (1...10).map {
        BillingChartAggregate.ChartPoint(label: String(format: "%02d", $0),
                                         value: Double($0), isCurrent: false)
    }
    let monthColumns = BillingChartGeometry.columns(month, in: plot)
    let expectedWidth = (plot.width - BillingChartGeometry.gap * 9) / 10
    assertEqual(abs((monthColumns.first?.frame.width ?? 0) - expectedWidth) < 0.001, true,
                "10 根按可用宽度均分（未触发 26pt 上限）")
    // 未封顶时总跨度正好等于绘图区宽（首柱贴左边缘、末柱贴右边缘）
    let monthSpan = (monthColumns.last?.frame.maxX ?? 0) - (monthColumns.first?.frame.minX ?? 0)
    assertEqual(abs(monthSpan - plot.width) < 0.001, true,
                "10 根横向填满绘图区（未触发上限时不居中留白）")

    // 上限生效的边界：根数少到「均分宽 > 上限」时才封顶
    let three = (1...3).map {
        BillingChartAggregate.ChartPoint(label: String(format: "%02d", $0),
                                         value: Double($0), isCurrent: false)
    }
    assertEqual(BillingChartGeometry.columns(three, in: plot).first?.frame.width ?? 0,
                BillingChartGeometry.maxBarWidth, "3 根时柱宽封顶并居中")

    // 空序列 / 零尺寸不崩、不出柱
    assertEqual(BillingChartGeometry.columns([], in: plot).count, 0, "空序列没有柱")
    assertEqual(BillingChartGeometry.columns(week, in: CGRect(x: 0, y: 0, width: 0, height: 76)).count,
                0, "零宽绘图区不出柱")

    // 命中判定：落在柱上给序号，落在两端留白里返回 nil（不硬命中最近一根）
    assertEqual(BillingChartGeometry.columnIndex(at: columns[3].frame.midX, columns: columns), 3,
                "命中第 4 根")
    assertEqual(BillingChartGeometry.columnIndex(at: plot.minX + 1, columns: columns), nil,
                "左侧留白不命中任何柱")
}

// MARK: - 刻度与悬停文案

private func captionAndTickTests() {
    let point = BillingChartAggregate.ChartPoint(label: "16", value: 1_204, isCurrent: true)
    assertEqual(BillingChartGeometry.caption(point, granularity: .hour, metric: .requests),
                "16 时 · 1,204", "24h 粒度写「时」")
    assertEqual(BillingChartGeometry.caption(point, granularity: .day, metric: .requests),
                "16 日 · 1,204", "7d / 30d 粒度写「日」（改造前恒写「时」）")
    assertEqual(BillingChartGeometry.captionUnit(for: .hour), "时", "小时粒度单位")
    assertEqual(BillingChartGeometry.captionUnit(for: .day), "日", "天粒度单位")

    let spend = BillingChartAggregate.ChartPoint(label: "16", value: 0.42, isCurrent: false)
    assertEqual(BillingChartGeometry.caption(spend, granularity: .day, metric: .spend),
                "16 日 · $0.42", "金额型悬停给美元符号")

    // 刻度值与柱高同一基准：峰值档 = peak、中点档 = peak / 2
    assertEqual(BillingChartGeometry.tickValue(peak: 1_204, fraction: 1), 1_204, "峰值刻度 = 峰值")
    assertEqual(BillingChartGeometry.tickValue(peak: 1_204, fraction: 0.5), 602, "中点刻度 = 峰值一半")
    assertEqual(BillingChartGeometry.tickValue(peak: 1_204, fraction: -1), 0, "越界档位夹到 0")
    assertContains(BillingChartGeometry.peakLabel(peak: 1_204, metric: .requests), "1.2",
                   "请求数峰值按数值单位缩写（1.2K）")

    // 网格线：1.0 档贴顶、0 档贴基线
    let plot = CGRect(x: 20, y: 0, width: 200, height: 76)
    assertEqual(BillingChartGeometry.gridLineY(fraction: 1, in: plot), plot.minY, "峰值网格线在顶部")
    assertEqual(BillingChartGeometry.gridLineY(fraction: 0, in: plot), plot.maxY, "0 档网格线在基线")
    assertEqual(BillingChartGeometry.gridFractionCount, 4, "4 条水平网格")

    // 矮图降级：二级页柱区只有 44pt，4 条网格 + 4 个刻度标签会糊成一片并压住柱子
    assertEqual(BillingChartGeometry.gridFractions(forHeight: 76).count, 4, "76pt 大图 4 条网格")
    assertEqual(BillingChartGeometry.gridFractions(forHeight: 44), [0.5, 1.0],
                "44pt 小图降级为 2 条网格")
    assertEqual(BillingChartGeometry.gridFractions(forHeight: BillingChartGeometry.scaleMinHeight).count,
                4, "阈值处仍按大图（≥ 阈值）")
}

// MARK: - 首帧范围对齐

private func rangeAlignmentTests() {
    // 现场根因：页级 7d、Open Design 默认 24h → 首帧必须把它拉到 7d
    let openDesign = BillingRangeAlignment.Candidate(
        id: "open-design", supportsUsage: true,
        supportedRanges: [.last24Hours, .last7Days], currentRange: .last24Hours)
    assertEqual(BillingRangeAlignment.idsNeedingAlignment([openDesign], pageRange: .last7Days),
                ["open-design"], "页级 7d 时把停在 24h 的 provider 拉过来")

    // 已经对齐的不再重复出网
    let aligned = BillingRangeAlignment.Candidate(
        id: "ollama", supportsUsage: true,
        supportedRanges: BillingRange.allCases, currentRange: .last7Days)
    assertEqual(BillingRangeAlignment.idsNeedingAlignment([aligned], pageRange: .last7Days),
                [], "已对齐的 provider 不重复通知（否则每次刷新多打一次请求）")

    // 不支持的档不通知（切过去必然 400）
    assertEqual(BillingRangeAlignment.idsNeedingAlignment([openDesign], pageRange: .last30Days),
                [], "provider 不支持的档不发请求")

    // 纯余额型没有用量请求可发
    let balanceOnly = BillingRangeAlignment.Candidate(
        id: "deepseek", supportsUsage: false,
        supportedRanges: BillingRange.allCases, currentRange: .last24Hours)
    assertEqual(BillingRangeAlignment.idsNeedingAlignment([balanceOnly], pageRange: .last7Days),
                [], "纯余额型不参与用量范围对齐")

    // 多家混排：只挑该通知的，且保持注册顺序
    let mixed = [aligned, balanceOnly, openDesign]
    assertEqual(BillingRangeAlignment.idsNeedingAlignment(mixed, pageRange: .last7Days),
                ["open-design"], "混排里只挑需要对齐的那家")
}
