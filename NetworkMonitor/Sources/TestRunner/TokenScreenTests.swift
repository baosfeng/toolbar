import Foundation
import NetworkMonitorUI

// MARK: - Token 分屏契约测试

// 覆盖：2 屏标题与顺序、每个区块唯一归属一屏、blocks(for:) 覆盖全部区块且不重复、
// 具体归属（防漂移，改屏结构必须同步改契约）、每屏页脚。
//
// v3 收敛背景：改前 4 屏每屏只用掉约 300/409pt，下方常年空白、看全数据要切三次屏。
// 现在 2 屏（总览 / 分布），缓存命中从独立屏降级为二级页（TokenDetailKind.cache）。

private func testTokenScreenTitles() {
    assertEqual(TokenScreen.allCases.count, 2, "2 个屏")
    assertEqual(TokenScreen.titles, ["总览", "分布"], "屏切换条文案与顺序")
    assertEqual(TokenScreen(rawValue: 0), TokenScreen.overview, "分段下标 0 = 总览")
    assertEqual(TokenScreen(rawValue: 1), TokenScreen.distro, "分段下标 1 = 分布")
    assertEqual(TokenScreen(rawValue: 2), nil, "越界下标不映射到任何屏")
    print("✅ Token 屏标题与顺序 works")
}

private func testTokenScreenBlockOwnership() {
    // 每个区块在两个屏里恰好出现一次（画两遍 / 哪屏都不显示都是错）
    for block in TokenScreenBlock.allCases {
        let owners = TokenScreen.allCases.filter { TokenScreen.blocks(for: $0).contains(block) }
        assertEqual(owners.count, 1, "区块「" + block.title + "」只能归属一个屏")
        assertEqual(owners.first == TokenScreen.screen(for: block), true,
                    "区块「" + block.title + "」的归属屏与 screen(for:) 一致")
    }
    // 两屏合起来覆盖全部区块，且不重复
    let all = TokenScreen.allCases.flatMap { TokenScreen.blocks(for: $0) }
    assertEqual(all.count, TokenScreenBlock.allCases.count, "两屏区块数 = 全部区块数（无重复）")
    assertEqual(Set(all), Set(TokenScreenBlock.allCases), "两屏覆盖全部区块（无遗漏）")
    // 每屏至少一块
    for screen in TokenScreen.allCases {
        assertEqual(TokenScreen.blocks(for: screen).isEmpty, false,
                    "「" + screen.title + "」至少一个区块")
    }
    print("✅ Token 区块唯一归属 works")
}

private func testTokenScreenBlockMapping() {
    assertEqual(TokenScreen.blocks(for: .overview),
                [.hero, .familyCards, .cacheHit, .hourChart],
                "总览 = Hero + 四族卡 + 缓存命中条 + 主图")
    assertEqual(TokenScreen.blocks(for: .distro), [.distro, .compare],
                "分布 = 维度分段与占比条 + 今日 vs 昨日")
    assertEqual(TokenScreen.screen(for: .cacheHit), .overview, "缓存命中条在总览")
    assertEqual(TokenScreen.screen(for: .hourChart), .overview, "主图在总览")
    assertEqual(TokenScreen.screen(for: .compare), .distro, "今日 vs 昨日在分布屏")
    assertEqual(TokenScreen.screen(for: .distro), .distro, "分布块在分布屏")
    assertEqual(TokenScreenBlock.cacheHit.title, "缓存命中条", "总览缓存条台账名")
    print("✅ Token 区块归属映射 works")
}

private func testTokenScreenFooters() {
    // 两屏页脚都是状态带（峰 / 昨 / 缓存 / 命中），内容滚动时钉在屏底
    assertEqual(TokenScreen.allCases.map { $0.footer }, [.stateBand, .stateBand],
                "两屏页脚都是状态带")
    assertEqual(TokenScreenFooter.allCases.count, 1, "页脚只有状态带一种")
    assertEqual(TokenScreenFooter.stateBand.title, "状态带", "页脚台账名")
    print("✅ Token 屏页脚契约 works")
}

private func testTokenScreenDensity() {
    // 密度判据：两屏的区块数都不少于 2（一屏只放一块 = 又回到「信息分散」）
    for screen in TokenScreen.allCases {
        assertEqual(TokenScreen.blocks(for: screen).count >= 2, true,
                    "「" + screen.title + "」至少两块（密度下限）")
    }
    // 屏数收敛的直接判据：2 个，不再是 4 个
    assertEqual(TokenScreen.allCases.count <= 2, true, "屏数不超过 2（两屏收敛）")
    print("✅ Token 屏密度下限 works")
}

func runTokenScreenTests() {
    print("\n🧪 Testing Token 分屏契约（2 屏 / 区块唯一归属 / 屏页脚 / 密度下限）...")
    testTokenScreenTitles()
    testTokenScreenBlockOwnership()
    testTokenScreenBlockMapping()
    testTokenScreenFooters()
    testTokenScreenDensity()
    print("✅ Token 分屏契约 works")
}
