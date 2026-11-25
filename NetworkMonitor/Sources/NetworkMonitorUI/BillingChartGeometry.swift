import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 额度柱图几何（纯逻辑，可单测）

/// 柱图几何口径 —— 值序列 → 柱矩形 / 网格档位 / 刻度文案 / 悬停粒度
///
/// 存在理由：柱宽、居中、最小柱高、基线、网格档位与悬停粒度都是「读数口径」，
/// 留在视图里（App 是可执行 target）就一条都断言不了。抽成纯函数后 TestRunner 能直接验
/// 「30 天 10 根不再挤成 1pt」「最小柱高 2pt」「7d 的 caption 写日不是时」。
///
/// 坐标系：全部按 flipped（原点左上、y 向下）给，与 BillingChartBarsView.isFlipped 一致 ——
/// 调用方拿到 rect 直接画，不再自己翻，避免两套口径漂移。
public enum BillingChartGeometry {

    /// 单根柱
    public struct Column: Equatable {
        /// 序号（0 = 最左）
        public let index: Int
        /// 整列命中区（宽 = 柱宽，不含 gap）
        public let frame: CGRect
        /// 柱体（自基线向上；值 0 时高度为 0，由视图决定不画）
        public let bar: CGRect
        /// 绘图值
        public let value: Double
        /// 是否最新一格（视图用图表语义色高亮，不用文本强调色）
        public let isCurrent: Bool
    }

    /// 柱宽上限 —— 根数少的档（24h 8 根 / 7d 7 根）全宽均分会得到 30pt+ 的胖柱
    ///
    /// 卡内绘图区实测约 256pt：7 根均分 34.9pt（太胖，近方形）、10 根均分 24.2pt（合适）。
    /// 上限取 32 而不是 26：26 时 7 根只占 194pt、两侧各留 31pt 空白，整块图缩成中间一坨；
    /// 32 时两侧各留 10pt，既限制胖柱又保持占满。封顶后余量均分到两端（居中）。
    public static let maxBarWidth: CGFloat = 32
    /// 柱宽下限 —— 30d 10 根在窄宽下仍要能分辨
    public static let minBarWidth: CGFloat = 3
    /// 柱间距（与 Token 页同档）
    public static let gap: CGFloat = 2
    /// 最小柱高 —— 值很小但不为零时也要看得见（否则读作这一段没有用量）
    public static let minBarHeight: CGFloat = 2
    /// 柱顶圆角
    public static let barRadius: CGFloat = 2
    /// 基线厚度（1pt 实线，压在柱底；柱浮在轨道上没有基线正是「不像柱状图」的主因）
    public static let baselineHeight: CGFloat = 1

    /// 水平网格档位（自基线起算，1.0 = 峰值）
    ///
    /// 4 条而不是 3 条：柱区抬到 76pt 后间隔约 19pt，既不糊成一片也能读出中间量。
    public static let gridFractions: [CGFloat] = [0.25, 0.5, 0.75, 1.0]
    /// 网格条数（视图与断言共用，别在两处各数一遍）
    public static var gridFractionCount: Int { gridFractions.count }

    /// 画 4 条网格 + 左侧刻度所需的最小高度
    ///
    /// 二级页柱区只有 44pt：4 条网格加 4 个刻度标签会糊成一片、标签还会压住柱子，
    /// 因此小图降级为「基线 + 2 条网格 + 不画刻度栏」。
    public static let scaleMinHeight: CGFloat = 60

    /// 按绘图高度取网格档位（大图 4 条、小图 2 条）
    public static func gridFractions(forHeight height: CGFloat) -> [CGFloat] {
        height >= scaleMinHeight ? gridFractions : [0.5, 1.0]
    }

    /// 值序列 → 柱矩形（柱宽有上限、整体居中、自基线向上增长）
    ///
    /// - Parameters:
    ///   - points: 图表点（isCurrent 决定高亮，value 决定高度）
    ///   - plot: 绘图区（flipped：minY 是顶部、maxY 是基线）
    public static func columns(_ points: [BillingChartAggregate.ChartPoint],
                               in plot: CGRect) -> [Column] {
        guard !points.isEmpty, plot.width > 0, plot.height > 0 else { return [] }
        let count = CGFloat(points.count)
        let available = plot.width - gap * (count - 1)
        guard available > 0 else { return [] }
        let width = min(maxBarWidth, max(minBarWidth, available / count))
        // 居中：柱宽被上限卡住后左右余量均分，30d 的 10 根不会全挤在左半边
        let total = width * count + gap * (count - 1)
        let originX = plot.minX + max((plot.width - total) / 2, 0)
        let peak = max(points.map(\.value).max() ?? 0, .leastNonzeroMagnitude)

        return points.enumerated().map { index, point in
            let x = originX + CGFloat(index) * (width + gap)
            let frame = CGRect(x: x, y: plot.minY, width: width, height: plot.height)
            let ratio = min(max(point.value / peak, 0), 1)
            // 自基线（plot.maxY）向上长：flipped 里 y 小 = 视觉在上
            let height = point.value > 0 ? max(minBarHeight, plot.height * CGFloat(ratio)) : 0
            let bar = CGRect(x: x, y: plot.maxY - height, width: width, height: height)
            return Column(index: index, frame: frame, bar: bar,
                          value: point.value, isCurrent: point.isCurrent)
        }
    }

    /// 命中判定：落点是第几根柱（nil = 落在两端留白或柱区外，不该硬命中最近一根）
    public static func columnIndex(at x: CGFloat, columns: [Column]) -> Int? {
        columns.first { x >= $0.frame.minX && x <= $0.frame.maxX }?.index
    }

    /// 网格线 y 坐标（flipped，自基线向上按 fraction 抬升）
    public static func gridLineY(fraction: CGFloat, in plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * min(max(fraction, 0), 1)
    }

    /// 刻度值（与柱高同一归一化基准，不另算一套）
    public static func tickValue(peak: Double, fraction: CGFloat) -> Double {
        max(peak, 0) * Double(min(max(fraction, 0), 1))
    }

    /// 刻度文案（请求数跟随设置页「数值单位」K/M/B 或 万/亿；金额保留两位）
    ///
    /// 金额不缩写：$0.42 缩成 $0.4 会让刻度读起来像整数。
    public static func tickLabel(peak: Double, fraction: CGFloat,
                                 metric: BillingChartAggregate.Metric) -> String {
        let value = tickValue(peak: peak, fraction: fraction)
        switch metric {
        case .requests: return NumberUnits.scale(value).text
        case .spend: return "$" + GroupedNumberFormatting.exact(value, maxFractionDigits: 2)
        }
    }

    /// 峰值刻度（最上面一条）
    public static func peakLabel(peak: Double, metric: BillingChartAggregate.Metric) -> String {
        tickLabel(peak: peak, fraction: 1, metric: metric)
    }

    /// 全部刻度文案（自下而上，与 gridFractions 一一对应）
    ///
    /// 视图拿这套标签自己量宽算刻度栏宽度：UI 库不 import AppKit，量文字必须回到视图层
    /// （字体从 PaneCardStyle 取），但「画哪几个值」这条口径留在纯函数里。
    public static func tickLabels(peak: Double,
                                  metric: BillingChartAggregate.Metric) -> [String] {
        gridFractions.map { tickLabel(peak: peak, fraction: $0, metric: metric) }
    }

    /// 悬停 / 读屏的粒度单位 —— 24h 按小时、7d / 30d 按天
    ///
    /// 改造前 caption 恒写「时」，7d 的「16 时 · 1,204」是错的（16 是日不是时）。
    public static func captionUnit(for granularity: BillingGranularity) -> String {
        granularity == .hour ? "时" : "日"
    }

    /// 单根柱的悬停文案：「14 时 · 1,204」/「16 日 · 1,204」
    public static func caption(_ point: BillingChartAggregate.ChartPoint,
                               granularity: BillingGranularity,
                               metric: BillingChartAggregate.Metric) -> String {
        let unit = captionUnit(for: granularity)
        let text: String
        switch metric {
        case .requests:
            text = GroupedNumberFormatting.integer(Int(point.value.rounded()))
        case .spend:
            text = "$" + GroupedNumberFormatting.exact(point.value, maxFractionDigits: 2)
        }
        return point.label + " " + unit + " · " + text
    }
}
