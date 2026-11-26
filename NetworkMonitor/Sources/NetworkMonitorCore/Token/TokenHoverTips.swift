import Foundation

// MARK: - 悬停文案：主图柱 / 主图卡动作按钮

/// 主图悬停与动作说明的文案口径（纯函数，TestRunner 直接断言）
///
/// 用户原话：「鼠标放上去也没任何的反应，也没提示等信息」。主图柱形改前只有点击通道
/// （点柱开单桶页），没有任何悬停反馈 —— 一根柱到底是多少、属于哪个时段，只能靠点进去。
///
/// 文案必须在 Core 里生成而不是写在视图里：视图拿不到「第几根 / 共几根」的稳定边界，
/// 而「第一个桶 / 最后一个桶 / 空桶」这三处恰恰是最容易写错的地方。
package enum TokenHoverTips {

    /// 单根柱的悬停文案
    ///
    /// 四段：时间 → 总量 → 三段构成 → 请求数与命中率。空桶只给「无数据」，
    /// 不写「0」堆出来的四行（那会让人以为这里真的有 0 消耗的记录）。
    ///
    /// - Parameters:
    ///   - bucket: 该桶数据
    ///   - index: 桶下标（0 起）
    ///   - count: 桶总数
    ///   - isHour: 桶是否为小时桶（今日 24 桶）；false = 按天桶
    package static func bucketTip(_ bucket: TokenBucket, index: Int, count: Int,
                                  isHour: Bool) -> String {
        let position = positionLabel(index: index, count: count)
        guard bucket.total > 0 || bucket.request > 0 else {
            return bucket.label + "（" + position + "）\n无数据"
        }
        var lines: [String] = [bucket.label + "（" + position + "）"]
        if bucket.total > 0 {
            lines.append("总量 " + TokenFormatting.tokens(bucket.total) + " tok")
            lines.append("缓存读 " + TokenFormatting.tokens(bucket.cache)
                + " · 未缓存 " + TokenFormatting.tokens(bucket.uncached)
                + " · 输出 " + TokenFormatting.tokens(bucket.output))
            lines.append("命中率 " + TokenFormatting.percent(TokenDerive.hitRate(bucket)))
        }
        if bucket.request > 0 {
            lines.append("请求 " + TokenFormatting.grouped(bucket.request) + " 次")
        }
        let unit = isHour ? "小时" : "天"
        lines.append("点击可打开这" + unit + "的明细")
        return lines.joined(separator: "\n")
    }

    /// 桶在整个序列里的位置文案：「第 3/24 个」
    ///
    /// 越界下标（视图算错列号时）不崩、不输出怪异值：夹到 [1, max(count, 1)]。
    package static func positionLabel(index: Int, count: Int) -> String {
        let total = max(count, 1)
        let clamped = min(max(index, 0), total - 1)
        return "第 " + String(clamped + 1) + "/" + String(total) + " 个"
    }

    /// 鼠标 x 落在第几列（nil = 不在任何列上：落在左侧刻度栏 / 视图外）
    ///
    /// 与点击通道（`TokenBarsView.mouseUp`）同一套列宽口径：列宽 = (绘图区宽 − 间隙) ÷ 列数，
    /// 在刻度栏里返回 nil —— 否则鼠标划过左侧刻度时最左那根柱会一直亮着。
    ///
    /// - Parameters:
    ///   - x: 鼠标在视图坐标里的 x（从左边界算）
    ///   - plotMinX: 绘图区左边界（开了刻度栏时 = 刻度栏宽度）
    ///   - plotWidth: 绘图区宽度
    ///   - count: 列数（<= 0 时返回 nil）
    ///   - gap: 列间隙（与绘制同值）
    package static func columnIndex(x: Double, plotMinX: Double, plotWidth: Double,
                                    count: Int, gap: Double = 2) -> Int? {
        guard count > 0, plotWidth > 0 else { return nil }
        guard x >= plotMinX else { return nil }
        let columnWidth = max(1, (plotWidth - gap * Double(count - 1)) / Double(count))
        let index = Int((x - plotMinX) / (columnWidth + gap))
        guard index >= 0, index < count else { return nil }
        return index
    }

    /// 主图卡「切：」按钮的悬停说明（按钮改图标后，语义只能靠 tooltip 与读屏承载）
    package static func toggleHint(hourView: TokenHourView) -> String {
        let next = hourView == .stack ? "对比" : "堆叠"
        return "切换主图形态：当前" + hourView.title + "，点击改为" + next
    }

    /// 主图卡「指标切换」按钮的悬停说明
    package static func metricHint(metric: TokenChartMetric) -> String {
        if metric == .total {
            return "当前画三段总量（缓存读 + 未缓存 + 输出），点击改为画请求数"
        }
        return "当前画请求数，点击改为画三段总量"
    }

    /// 「14 天 ›」入口的悬停说明
    package static func trendHint() -> String {
        "打开天趋势：近 14 天逐日用量与命中率"
    }

    /// Hero 主数值的口径说明
    ///
    /// 用户原话「鼠标放上去也没任何的反应」—— Hero 是全界面最大的一行字，也是口径最该被
    /// 解释的一处（三段相加？含不含缓存读？），此前无 toolTip。
    package static func heroHint(title: String, delta: String) -> String {
        var lines = [title + " = 缓存读 + 未缓存输入 + 输出（三段 tok 相加，请求数不进这个合计）"]
        if !delta.isEmpty { lines.append("较昨日的对比按同一时段的已发生小时数对齐，不是整日对整日") }
        return lines.joined(separator: "\n")
    }

    /// 缓存命中条的悬停说明
    ///
    /// 直接复用 `TokenCachePage.heroSub`（Core 已经把「分母是什么、与主面板同范围」写在里面），
    /// 这里只补一句「点开能看什么」—— 否则同一口径会出现两处措辞，久了必然分叉。
    package static func cacheHitHint(rateText: String, subline: String) -> String {
        "缓存命中率 " + rateText + "% · " + subline + "。整条可点击打开缓存详细页"
    }

    /// 四族卡的悬停说明（点击行为 + 该族的口径）
    package static func familyCardHint(metric: TokenMetric) -> String {
        switch metric {
        case .uncached:
            return "未缓存输入：本次实际送进模型的输入 tok。点击查看按小时明细"
        case .output:
            return "输出：模型生成的 tok。点击查看按小时明细"
        case .cache:
            return "缓存读：命中提示缓存的输入 tok，单价通常远低于未缓存输入。点击查看按小时明细"
        case .request:
            return "请求数：请求次数，与 tok 不同源，不计入总量。点击查看按小时明细"
        }
    }
}
