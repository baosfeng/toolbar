import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板筛选芯片（类型 / 来源 App / 日期）

/// 筛选芯片的纯逻辑守门测试
///
/// 钉住四件事：
/// 1. 芯片模型自描述 —— 打包成 kind+value 后能还原，错值按「不限制」而不是清空结果；
/// 2. 叠加口径 —— 同类「或」、异类「且」，空芯片不过滤；
/// 3. 日期四档 —— 按自然日分档且互斥，不重叠不遗漏；
/// 4. 来源清单 —— 去重、按出现次数降序、取前 N，空名与 nil 不进清单。
func runClipboardFilterTokenTests() {
    print("🧪 Testing clipboard filter tokens...")
    do {
        let calendar = Calendar(identifier: .gregorian)
        // 固定参照时刻：某日 15:00（本地时区），后续全部按它算相对日期
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 17
        components.hour = 15
        let now = calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }

        // MARK: 芯片模型

        assertEqual(ClipboardFilterToken.type(.text).label, "文本", "类型芯片取中文名")
        assertEqual(ClipboardFilterToken.source("Safari").label, "Safari", "来源芯片直接显示 App 名")
        assertEqual(ClipboardFilterToken.date(.last7Days).label, "近 7 天", "日期芯片取档位文案")
        assertEqual(ClipboardFilterToken.type(.text).id, "type:1", "芯片标识 = kind + 原始值")
        assertEqual(ClipboardFilterToken.source("Safari").typeFilter, nil, "非类型芯片取不到类型")
        assertEqual(ClipboardFilterToken.date(.today).sourceName, nil, "非来源芯片取不到 App 名")
        assertEqual(ClipboardFilterToken(kind: .type, value: "99").label, "99",
                    "取值非法时回退原始串，不静默丢芯片")
        assertEqual(ClipboardFilter.allCases.filter { $0.isChip }.count, 3, "类型芯片三枚（全部不占芯片位）")
        assertEqual(ClipboardFilter.all.isChip, false, "「全部」不是芯片")

        let textItem = ClipboardItem(kind: .text, preview: "文本",
                                     contentHash: "ft-text", sourceAppName: "Safari", createdAt: now)
        let rtfItem = ClipboardItem(kind: .rtf, preview: "富文本",
                                    contentHash: "ft-rtf", sourceAppName: "Safari", createdAt: now)
        let imageItem = ClipboardItem(kind: .image, preview: "图片",
                                      contentHash: "ft-image", sourceAppName: "Preview", createdAt: daysAgo(1))
        let pinnedItem = ClipboardItem(kind: .text, preview: "收藏",
                                       contentHash: "ft-pin", sourceAppName: "Terminal",
                                       isPinned: true, createdAt: daysAgo(10))
        let oldItem = ClipboardItem(kind: .text, preview: "老",
                                    contentHash: "ft-old", sourceAppName: "Terminal", createdAt: daysAgo(60))
        let items = [textItem, rtfItem, imageItem, pinnedItem, oldItem]

        // MARK: 叠加匹配

        assertEqual(ClipboardFilterMatcher.matches(textItem, tokens: [], now: now, calendar: calendar), true,
                    "没有芯片时不过滤")
        assertEqual(ClipboardFilterMatcher.matches(textItem, tokens: [.type(.text)], now: now, calendar: calendar), true,
                    "类型芯片：文本命中")
        assertEqual(ClipboardFilterMatcher.matches(rtfItem, tokens: [.type(.text)], now: now, calendar: calendar), true,
                    "类型芯片：富文本也算文本")
        assertEqual(ClipboardFilterMatcher.matches(imageItem, tokens: [.type(.text)], now: now, calendar: calendar), false,
                    "类型芯片：图片不算文本")
        assertEqual(ClipboardFilterMatcher.matches(pinnedItem, tokens: [.type(.pinned)], now: now, calendar: calendar), true,
                    "类型芯片：收藏档按 isPinned")

        // 同类「或」：来源 Safari 或 Terminal 都能过
        let twoSources = [ClipboardFilterToken.source("Safari"), ClipboardFilterToken.source("Terminal")]
        let orMatched = items.filter {
            ClipboardFilterMatcher.matches($0, tokens: twoSources, now: now, calendar: calendar)
        }
        assertEqual(orMatched.count, 4, "同类芯片是「或」：Safari 2 条 + Terminal 2 条")

        // 异类「且」：来源 Safari 且 今天
        let safariToday = [ClipboardFilterToken.source("Safari"), ClipboardFilterToken.date(.today)]
        let andMatched = items.filter {
            ClipboardFilterMatcher.matches($0, tokens: safariToday, now: now, calendar: calendar)
        }
        assertEqual(andMatched.count, 2, "异类芯片是「且」：Safari 且 今天 2 条")
        assertEqual(ClipboardFilterMatcher.matches(oldItem, tokens: safariToday, now: now, calendar: calendar), false,
                    "「且」关系：来源不对就不命中")

        // 边界：非法取值按「不限制」，不把整批结果清空
        let broken = ClipboardFilterToken(kind: .date, value: "not-a-range")
        assertEqual(ClipboardFilterMatcher.matches(oldItem, tokens: [broken], now: now, calendar: calendar), true,
                    "日期取值非法时按不限制处理")

        // MARK: 日期四档

        assertEqual(ClipboardDateRange.today.contains(now, now: now, calendar: calendar), true, "今天档：此刻命中")
        assertEqual(ClipboardDateRange.today.contains(daysAgo(1), now: now, calendar: calendar), false,
                    "今天档：昨天不命中")
        assertEqual(ClipboardDateRange.last7Days.contains(daysAgo(6), now: now, calendar: calendar), true,
                    "近 7 天档：含第 6 天")
        assertEqual(ClipboardDateRange.last7Days.contains(daysAgo(7), now: now, calendar: calendar), false,
                    "近 7 天档：第 7 天已出档")
        assertEqual(ClipboardDateRange.last30Days.contains(daysAgo(29), now: now, calendar: calendar), true,
                    "近 30 天档：含第 29 天")
        assertEqual(ClipboardDateRange.last30Days.contains(daysAgo(30), now: now, calendar: calendar), false,
                    "近 30 天档：第 30 天已出档")
        assertEqual(ClipboardDateRange.earlier.contains(daysAgo(30), now: now, calendar: calendar), true,
                    "更早档：第 30 天起")
        assertEqual(ClipboardDateRange.earlier.contains(now, now: now, calendar: calendar), false, "更早档：今天不算")
        let future = now.addingTimeInterval(3_600)
        assertEqual(ClipboardDateRange.today.contains(future, now: now, calendar: calendar), true,
                    "时钟漂移导致的未来时间归入今天，不产生空档")

        // 互斥且完备：任何时刻恰好落在一档
        for offset in [0, 1, 6, 7, 29, 30, 400] {
            let date = daysAgo(offset)
            let hits = ClipboardDateRange.allCases.filter { $0.contains(date, now: now, calendar: calendar) }
            assertEqual(hits.count, 1, "第 " + String(offset) + " 天恰好命中一档（四档互斥且完备）")
        }

        // MARK: 来源清单

        let sources = ClipboardSourceCatalog.topSources(items: items)
        assertEqual(sources.map { $0.name }, ["Safari", "Terminal", "Preview"], "来源去重 + 按出现次数降序")
        assertEqual(sources.map { $0.count }, [2, 2, 1], "次数与实际条目一致")
        assertEqual(ClipboardSourceCatalog.topSources(items: items, limit: 2).count, 2, "limit 截断取前 N")
        assertEqual(ClipboardSourceCatalog.topSources(items: items, limit: 0).isEmpty, true, "limit ≤ 0 返回空")
        assertEqual(ClipboardSourceCatalog.topSources(items: items, limit: -3).isEmpty, true, "负 limit 返回空")
        let nameless = ClipboardItem(kind: .text, preview: "无来源", contentHash: "ft-nil")
        let blankSource = ClipboardItem(kind: .text, preview: "空名", contentHash: "ft-blank",
                                        sourceAppName: "   ")
        assertEqual(ClipboardSourceCatalog.topSources(items: [nameless, blankSource]).isEmpty, true,
                    "来源缺失或全空白的条目不进候选清单")
        assertEqual(ClipboardSourceCatalog.topSources(items: []).isEmpty, true, "没有条目时清单为空")

        print("✅ Clipboard filter tokens (type / source / date) works")
    }
}
