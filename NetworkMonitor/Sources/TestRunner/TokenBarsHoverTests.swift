import Foundation
import NetworkMonitorCore

// MARK: - 主图柱形 / 卡头动作的悬停文案

/// 覆盖「鼠标放上去也没任何的反应，也没提示等信息」里主图那一段的文案与命中判据。
///
/// 为什么要专门测「第一个桶 / 最后一个桶 / 空桶」：悬停列号是按鼠标 x 算出来的，
/// 边界差一列就会把「00 时」的文案挂到「01 时」的柱上 —— 看起来有反应，读数却是错的。
func runTokenBarsHoverTests() {
    print("\n🧪 Testing Token 主图悬停文案（柱 / 卡头动作按钮）...")
    testBucketTipFull()
    testBucketTipEmpty()
    testColumnIndexBoundaries()
    testToggleHints()
    print("✅ Token 主图悬停文案（柱 / 动作按钮）works")
}

// MARK: - 单柱文案

private func testBucketTipFull() {
    let bucket = TokenBucket(label: "13时", uncached: 1_000, output: 500, cache: 3_000, request: 7)
    let tip = TokenHoverTips.bucketTip(bucket, index: 13, count: 24, isHour: true)
    assertEqual(tip.contains("13时"), true, "文案含时间标签")
    assertEqual(tip.contains("第 14/24 个"), true, "文案含位置（第 14/24 个）")
    assertEqual(tip.contains(TokenFormatting.tokens(bucket.total)), true, "文案含总量")
    assertEqual(tip.contains("缓存读"), true, "文案含缓存读")
    assertEqual(tip.contains("未缓存"), true, "文案含未缓存")
    assertEqual(tip.contains("输出"), true, "文案含输出")
    assertEqual(tip.contains("命中率"), true, "文案含命中率")
    assertEqual(tip.contains("7 次"), true, "文案含请求数")
    assertEqual(tip.contains("点击可打开这小时的明细"), true, "文案末行提示可点击（小时桶）")
    assertEqual(tip.components(separatedBy: "\n").count >= 5, true, "多行文案（每段一行）")

    let dayTip = TokenHoverTips.bucketTip(bucket, index: 0, count: 7, isHour: false)
    assertEqual(dayTip.contains("点击可打开这天的明细"), true, "按天桶写「这天」而不是「这小时」")
    assertEqual(dayTip.contains("第 1/7 个"), true, "第一个桶的位置文案")
    print("   · 小时桶样例：" + dayTip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

private func testBucketTipEmpty() {
    let empty = TokenBucket.empty
    let tip = TokenHoverTips.bucketTip(empty, index: 0, count: 24, isHour: true)
    assertEqual(tip.contains("无数据"), true, "空桶写「无数据」")
    assertEqual(tip.contains("0"), false, "空桶不输出一串 0（会让人以为这里真有 0 消耗记录）")
    assertEqual(tip.components(separatedBy: "\n").count, 2, "空桶只两行：标签 + 无数据")

    // 只有请求数、没有 tok 的桶：不该写成「总量 0 tok」
    let requestOnly = TokenBucket(label: "05时", uncached: 0, output: 0, cache: 0, request: 3)
    let requestTip = TokenHoverTips.bucketTip(requestOnly, index: 5, count: 24, isHour: true)
    assertEqual(requestTip.contains("总量"), false, "没有 tok 的桶不写「总量 0 tok」")
    assertEqual(requestTip.contains("3 次"), true, "但仍给出请求数")
}

// MARK: - 列命中边界

private func testColumnIndexBoundaries() {
    // 绘图区 0…240pt、24 列、间隙 2pt → 列宽 (240 - 23*2)/24 = 8.0833
    let plotWidth = 240.0
    let count = 24
    let gap = 2.0
    let columnWidth = (plotWidth - gap * Double(count - 1)) / Double(count)

    assertEqual(TokenHoverTips.columnIndex(x: 0, plotMinX: 0, plotWidth: plotWidth,
                                           count: count, gap: gap), 0,
                "最左端落在第一列（不是越界 -1）")
    assertEqual(TokenHoverTips.columnIndex(x: plotWidth - 0.001, plotMinX: 0, plotWidth: plotWidth,
                                           count: count, gap: gap), count - 1,
                "最右端落在最后一列（不是越界 24）")
    assertEqual(TokenHoverTips.columnIndex(x: plotWidth + 5, plotMinX: 0, plotWidth: plotWidth,
                                           count: count, gap: gap) == nil, true,
                "超出绘图区 → 没有命中列")
    assertEqual(TokenHoverTips.columnIndex(x: -1, plotMinX: 0, plotWidth: plotWidth,
                                           count: count, gap: gap) == nil, true,
                "左侧越界 → 没有命中列")
    // 刻度栏：绘图区从 22pt 起，落在刻度栏里的鼠标不该命中第一列
    assertEqual(TokenHoverTips.columnIndex(x: 10, plotMinX: 22, plotWidth: plotWidth,
                                           count: count, gap: gap) == nil, true,
                "落在左侧刻度栏 → 不命中任何列（否则最左柱会一直亮着）")
    assertEqual(TokenHoverTips.columnIndex(x: 22, plotMinX: 22, plotWidth: plotWidth,
                                           count: count, gap: gap), 0,
                "绘图区左边界正好是第一列")
    // 逐列验证：第 k 列中心落在第 k 列
    for index in 0..<count {
        let center = 22 + Double(index) * (columnWidth + gap) + columnWidth / 2
        assertEqual(TokenHoverTips.columnIndex(x: center, plotMinX: 22, plotWidth: plotWidth,
                                                count: count, gap: gap), index,
                    "第 \(index + 1) 列中心命中自己的列")
    }
    assertEqual(TokenHoverTips.columnIndex(x: 10, plotMinX: 0, plotWidth: 0, count: count, gap: gap) == nil,
                true, "绘图区宽度为 0 → 没有命中列")
    assertEqual(TokenHoverTips.columnIndex(x: 10, plotMinX: 0, plotWidth: plotWidth, count: 0, gap: gap) == nil,
                true, "没有列 → 没有命中列")
    assertEqual(TokenHoverTips.positionLabel(index: 0, count: 24), "第 1/24 个", "首个位置文案")
    assertEqual(TokenHoverTips.positionLabel(index: 23, count: 24), "第 24/24 个", "末个位置文案")
    assertEqual(TokenHoverTips.positionLabel(index: 99, count: 24), "第 24/24 个", "越界下标夹到末列（不输出第 100/24 个）")
    assertEqual(TokenHoverTips.positionLabel(index: -3, count: 24), "第 1/24 个", "负下标夹到首列")
}

// MARK: - 卡头动作按钮说明

private func testToggleHints() {
    let stack = TokenHoverTips.toggleHint(hourView: .stack)
    assertEqual(stack.contains("当前堆叠"), true, "提示写当前形态")
    assertEqual(stack.contains("对比"), true, "提示写点击后变成什么")
    let compare = TokenHoverTips.toggleHint(hourView: .compare)
    assertEqual(compare.contains("当前对比"), true, "对比态的提示")
    assertEqual(compare.contains("堆叠"), true, "对比态提示写点击改堆叠")

    let total = TokenHoverTips.metricHint(metric: .total)
    assertEqual(total.contains("三段总量"), true, "总量态提示写明三段")
    let request = TokenHoverTips.metricHint(metric: .request)
    assertEqual(request.contains("请求数"), true, "请求数态提示")

    assertEqual(TokenHoverTips.trendHint().contains("天趋势"), true, "天趋势入口的悬停说明")
    assertEqual(TokenHoverTips.heroHint(title: "今日总消耗", delta: "").contains("缓存读"), true,
                "Hero 口径说明含三段相加")
    assertEqual(TokenHoverTips.familyCardHint(metric: .request).contains("不计入总量"), true,
                "请求数族卡说明写明不计入总量")
    assertEqual(TokenHoverTips.cacheHitHint(rateText: "97.5", subline: "分母 1.2M").contains("分母 1.2M"), true,
                "缓存条说明复用 Core 的口径行")
}