import Foundation
import NetworkMonitorUI

// MARK: - Token 分屏契约测试

// 覆盖：4 屏标题与顺序、每个区块唯一归属一屏、blocks(for:) 覆盖全部区块且不重复、
// 具体归属（防漂移，改屏结构必须同步改契约）、每屏页脚（3× 状态带 + 1× 口径说明）。

private func testTokenScreenTitles() {
    assertEqual(TokenScreen.allCases.count, 4, "4 个屏")
    assertEqual(TokenScreen.titles, ["概览", "用量", "缓存", "排行"], "屏切换条文案与顺序")
    assertEqual(TokenScreen(rawValue: 0), TokenScreen.overview, "分段下标 0 = 概览")
    assertEqual(TokenScreen(rawValue: 2), TokenScreen.cache, "分段下标 2 = 缓存")
    assertEqual(TokenScreen(rawValue: 4), nil, "越界下标不映射到任何屏")
    print("✅ Token 屏标题与顺序 works")
}

private func testTokenScreenBlockOwnership() {
    // 每个区块在四屏里恰好出现一次（画两遍 / 哪屏都不显示都是错）
    for block in TokenScreenBlock.allCases {
        let owners = TokenScreen.allCases.filter { TokenScreen.blocks(for: $0).contains(block) }
        assertEqual(owners.count, 1, "区块「" + block.title + "」只能归属一个屏")
        assertEqual(owners.first == TokenScreen.screen(for: block), true,
                    "区块「" + block.title + "」的归属屏与 screen(for:) 一致")
    }
    // 四屏合起来覆盖全部区块，且不重复
    let all = TokenScreen.allCases.flatMap { TokenScreen.blocks(for: $0) }
    assertEqual(all.count, TokenScreenBlock.allCases.count, "四屏区块数 = 全部区块数（无重复）")
    assertEqual(Set(all), Set(TokenScreenBlock.allCases), "四屏覆盖全部区块（无遗漏）")
    // 每屏至少一块
    for screen in TokenScreen.allCases {
        assertEqual(TokenScreen.blocks(for: screen).isEmpty, false,
                    "「" + screen.title + "」至少一个区块")
    }
    print("✅ Token 区块唯一归属 works")
}

private func testTokenScreenBlockMapping() {
    assertEqual(TokenScreen.blocks(for: .overview),
                [.hero, .familyCards, .cacheHit, .overviewTrend, .compare],
                "概览 = Hero + 四族卡 + 缓存命中条 + 近 14 天 + 今日 vs 昨日")
    assertEqual(TokenScreen.blocks(for: .usage), [.hourChart, .trend],
                "用量 = 主图 + 天趋势（对比卡已挪到概览）")
    assertEqual(TokenScreen.blocks(for: .cache), [.cacheRing, .cacheTrend, .cacheCompare, .cacheStats],
                "缓存 = 环 + 趋势 + 对照 + 统计")
    assertEqual(TokenScreen.blocks(for: .ranking), [.distroBar, .distroRows],
                "排行 = 维度段与占比条 + Top 8")
    assertEqual(TokenScreen.screen(for: .compare), .overview, "今日 vs 昨日在概览")
    assertEqual(TokenScreen.screen(for: .overviewTrend), .overview, "近 14 天迷你走势在概览")
    assertEqual(TokenScreen.screen(for: .cacheHit), .overview, "缓存命中紧凑条在概览")
    assertEqual(TokenScreenBlock.cacheHit.title, "缓存命中条", "概览缓存条台账名")
    assertEqual(TokenScreen.screen(for: .hourChart), .usage, "主图在用量")
    assertEqual(TokenScreen.screen(for: .cacheStats), .cache, "样本统计在缓存")
    assertEqual(TokenScreen.screen(for: .distroRows), .ranking, "Top 8 在排行")
    print("✅ Token 区块归属映射 works")
}

private func testTokenScreenFooters() {
    // 每屏恰一个页脚：概览 / 用量 / 排行 = 状态带（内容滚动时钉在屏底），缓存 = 口径说明
    let footers = TokenScreen.allCases.map { $0.footer }
    assertEqual(footers.count, 4, "四屏各一个页脚")
    assertEqual(footers.filter { $0 == .stateBand }.count, 3, "三屏页脚是状态带")
    assertEqual(footers.filter { $0 == .cacheNote }.count, 1, "缓存屏页脚是口径说明")
    assertEqual(TokenScreen.footer(for: .overview), .stateBand, "概览页脚 = 状态带")
    assertEqual(TokenScreen.footer(for: .usage), .stateBand, "用量页脚 = 状态带")
    assertEqual(TokenScreen.footer(for: .ranking), .stateBand, "排行页脚 = 状态带")
    assertEqual(TokenScreen.footer(for: .cache), .cacheNote, "缓存页脚 = 口径说明")
    assertEqual(TokenScreenFooter.allCases.count, 2, "页脚只有两种（状态带 / 口径说明）")
    assertEqual(TokenScreenFooter.stateBand.title, "状态带", "页脚台账名")
    assertEqual(TokenScreenFooter.cacheNote.title, "口径说明", "页脚台账名")
    print("✅ Token 屏页脚契约 works")
}

func runTokenScreenTests() {
    print("\n🧪 Testing Token 分屏契约（4 屏 / 区块唯一归属 / 屏页脚）...")
    testTokenScreenTitles()
    testTokenScreenBlockOwnership()
    testTokenScreenBlockMapping()
    testTokenScreenFooters()
    print("✅ Token 分屏契约 works")
}
