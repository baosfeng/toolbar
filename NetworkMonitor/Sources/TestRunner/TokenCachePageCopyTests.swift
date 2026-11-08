import Foundation
import NetworkMonitorCore

// MARK: - 缓存命中二级页随范围：文案 / 缺上一周期 / 主面板同源
//
// 从 TokenCachePageTests.swift 拆出（那边超出 500 行 / 15360 字节门禁）。
// 本文件覆盖「文案怎么说」与「没有上一周期数据时怎么说」，数据与桶序列在另一个文件。
// 共用夹具（internal，跨文件）：cacheRangeSnapshot() / cacheNoPreviousSnapshot() / cacheModel(_:_:)。

/// 3) 文案随范围，旧口径彻底消失
func testCacheCopyFollowsRange() {
    let snapshot = cacheRangeSnapshot()
    for range in [TokenRange.today, .d7, .d30] {
        let page = cacheModel(snapshot, range).cachePage
        assertEqual(page.crumbMeta, range.title + "口径", "\(range.title) 面包屑 meta 取当前范围")
        assertEqual(page.heroUnit, "% · " + range.title + "命中", "\(range.title) Hero 单位带范围")
        assertEqual(page.heroSub.contains(range.title), true, "\(range.title) Hero 副标题带范围")
        assertEqual(page.heroSub.contains("与主面板同范围"), true,
                    "\(range.title) Hero 副标题声明与主面板同范围")
        assertEqual(page.trendAccessibility.contains(range.title), true,
                    "\(range.title) 走势图无障碍文案带范围")
        assertEqual(page.ringAccessibility.contains(range.title), true,
                    "\(range.title) 环形卡无障碍文案带范围")
        assertEqual(page.compareTitle.contains(range.title), true,
                    "\(range.title) 对照卡标题带范围")

        let copy = [page.crumbMeta, page.heroUnit, page.heroSub, page.trendTitle, page.trendMeta,
                    page.compareTitle, page.note].joined(separator: "|")
        for legacy in ["不随主面板范围切换", "固定 30 天", "固定今日 24 桶", "主数值取今日"] {
            assertEqual(copy.contains(legacy), false, "\(range.title) 缓存页文案不再出现「\(legacy)」")
        }
    }
    let titles = [TokenRange.today, .d7, .d30].map { cacheModel(snapshot, $0).cachePage.heroUnit }
    assertEqual(Set(titles).count, 3, "三档范围的 Hero 单位文案互不相同")
    // 面包屑 meta 与「按项目 / 按模型」同源写法（都是「{范围}口径」）
    let d7 = cacheModel(snapshot, .d7)
    assertEqual(d7.cachePage.crumbMeta, d7.distroCopy.projectsCrumbMeta,
                "缓存页与按项目页的面包屑口径写法一致")
    print("✅ 缓存命中页文案随范围（面包屑 / Hero / 走势 / 对照 / 说明卡）works")
}

/// 4) 上一周期无数据时不编数
func testCacheNoPreviousData() {
    let snapshot = cacheNoPreviousSnapshot()
    for range in [TokenRange.today, .d7, .d30] {
        let page = cacheModel(snapshot, range).cachePage
        assertEqual(page.hasPrevious, false, "\(range.title) 上一周期无数据")
        assertEqual(page.previousRateText, "—", "\(range.title) 上一周期命中率给「—」不给 0%")
        assertEqual(page.previousCacheText, "—", "\(range.title) 上一周期缓存读给「—」")
        assertEqual(page.deltaText, "—", "\(range.title) 差值给「—」")
        assertEqual(page.previousFraction, 0, "\(range.title) 无数据时对照条长度为 0")
        // 本周期数据仍在：不给假数不等于整页空白
        assertEqual(page.hasPrevious == false && page.heroValue.isEmpty, false,
                    "\(range.title) 本周期数值照常给出")
    }
    // 上一周期覆盖度：30 天窗口的前 30 天在索引里通常只有几天，必须写在对照卡头
    assertEqual(cacheModel(cacheNoPreviousSnapshot(), .d30).cachePage.compareMeta,
                "前一段仅 0/30 天有数据", "近 30 天上一周期无数据时写明 0/30")
    assertEqual(cacheModel(cacheRangeSnapshot(), .d7).cachePage.compareMeta, "同长度前一段",
                "上一周期满覆盖时不加缺口提示")
    assertEqual(cacheModel(cacheRangeSnapshot(), .today).cachePage.compareMeta, "同时段昨日",
                "今日范围不写小时缺口（24 小时里有空档是常态）")

    // 有数据的一侧不受影响
    let withPrevious = cacheModel(cacheRangeSnapshot(), .d7).cachePage
    assertEqual(withPrevious.hasPrevious, true, "上一周期有数据时 hasPrevious = true")
    assertEqual(withPrevious.previousRateText.contains("—"), false,
                "有数据时上一周期不再退化成「—」")
    print("✅ 缓存命中页上一周期无数据时给「—」（不编 0%，本周期照常）works")
}

/// 5) 主面板缓存卡与二级页同源
func testCachePaneModelSync() {
    let snapshot = cacheRangeSnapshot()
    for range in [TokenRange.today, .d7, .d30] {
        let model = cacheModel(snapshot, range)
        let page = model.cachePage
        assertEqual(model.hitText, page.heroValue, "\(range.title) 主面板大数字 = 二级页主数值")
        assertEqual(model.hitBucketText, page.bucketUnitText, "\(range.title) 主面板桶数文案 = 二级页")
        assertEqual(model.hitMeta.hasPrefix(range.title), true,
                    "\(range.title) 主面板缓存卡说明以当前范围开头")
        assertEqual(model.hitRateFraction, page.ringFraction, "\(range.title) 主面板环与二级页环同值")
    }
    let d7 = cacheModel(snapshot, .d7)
    assertEqual(d7.hitMeta, "近 7 天 " + d7.cachePage.heroValue + "%", "近 7 天主面板缓存卡说明")
    print("✅ 主面板缓存卡与二级页同源（大数字 / 桶数 / 序列 / 环形比例）works")
}

/// 套件入口（由 runTokenRangeConsistencyTests 调用，main.swift 调度不变）
func runTokenCachePageTests() {
    print("\n🧪 Testing 缓存命中二级页随范围（今日 / 近 7 天 / 近 30 天）...")
    testCacheBucketsFollowRange()
    testCacheValuesFollowRange()
    testCacheSeriesGaps()
    testCacheCopyFollowsRange()
    testCacheNoPreviousData()
    testCachePaneModelSync()
}