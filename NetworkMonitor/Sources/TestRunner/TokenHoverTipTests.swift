import Foundation
import NetworkMonitorCore

// MARK: - 分布行 / 占比条悬停文案（toolTip）测试
//
// 背景：同一模型（如 deepseek-v4.1-flash）来自多个 provider（ollama / open-design），
// 主面板「按模型」半宽卡只显示模型名，两行一模一样；provider 只能从悬停看到。
// 所以文案必须由 Core 纯函数生成（视图只做搬运），才能在这里逐条锁死：
// 1. 模型行同时给出 provider 与模型全名；
// 2. provider 缺失时不出现「provider —」这类半句话；
// 3. 项目行给出会话数与占比；
// 4. 占比条整条文案逐段可读（图例被截断时的唯一出口）。

func runTokenHoverTipTests() {
    print("\n🧪 Testing Token 分布行 / 占比条悬停文案（provider 可辨识）...")
    testModelRowTip()
    testModelRowTipWithoutProvider()
    testSameModelDifferentProviders()
    testProjectRowTip()
    testStackBarTip()
    testDistroRowFullName()
    testDistroAccessibilityCopy()
    print("✅ Token 悬停文案（模型行 / 项目行 / 占比条整条）works")
}

// MARK: - 模型行

private func testModelRowTip() {
    let models = [
        HarnessModelUsage(provider: "anthropic", model: "claude",
                          usage: HarnessTokenUsage(uncachedInput: 100, output: 0, cacheRead: 300, requestCount: 2)),
    ]
    let rows = TokenDerive.modelRows(tokenSnapshot(models: models), window: .today)
    assertEqual(rows.count, 1, "一个模型一行")
    let tip = rows[0].tip
    assertEqual(tip.contains("anthropic"), true, "模型行悬停文案含 provider")
    assertEqual(tip.contains("anthropic/claude"), true, "模型行悬停文案首行是 provider/模型全名")
    assertEqual(tip.contains(rows[0].amount), true, "模型行悬停文案含金额")
    assertEqual(tip.contains(TokenFormatting.percent(rows[0].share)), true, "模型行悬停文案含占比")
    assertEqual(tip.contains("命中"), true, "模型行悬停文案含命中率")
    assertEqual(tip.hasPrefix("anthropic/claude"), true, "首行以 provider/model 开头（同名模型靠它区分）")
    print("   · 模型行样例：" + tip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

private func testModelRowTipWithoutProvider() {
    let models = [
        HarnessModelUsage(provider: "", model: "local-model",
                          usage: HarnessTokenUsage(uncachedInput: 600, requestCount: 1)),
    ]
    let rows = TokenDerive.modelRows(tokenSnapshot(models: models), window: .today)
    let tip = rows[0].tip
    assertEqual(tip.contains("provider —"), false, "provider 为空时不出现「provider —」噪音")
    assertEqual(tip.contains("—"), false, "provider 为空时整条文案不出现破折号占位")
    assertEqual(tip.contains("local-model"), true, "provider 为空时仍然给出模型名")
    assertEqual(tip.hasPrefix("local-model"), true, "provider 为空时首行只有模型名，不留孤立斜杠")
    assertEqual(tip.contains("/"), false, "provider 为空时文案里没有斜杠拼名")
    // 正文（二级页说明行）仍沿用原口径，保持既有断言不变
    assertEqual(rows[0].sub, "provider — · 占 100.0% · 命中 0.0%", "正文 sub 口径未被悬停文案改动")
    print("   · provider 缺失样例：" + tip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

/// 用户反馈的原场景：同名模型来自两个 provider，两行正文一样、悬停必须能分开
private func testSameModelDifferentProviders() {
    let models = [
        HarnessModelUsage(provider: "ollama", model: "deepseek-v4.1-flash",
                          usage: HarnessTokenUsage(uncachedInput: 500, cacheRead: 500, requestCount: 1)),
        HarnessModelUsage(provider: "open-design", model: "deepseek-v4.1-flash",
                          usage: HarnessTokenUsage(uncachedInput: 300, cacheRead: 100, requestCount: 1)),
    ]
    let rows = TokenDerive.modelRows(tokenSnapshot(models: models), window: .today)
    assertEqual(rows.count, 2, "两个 provider 各一行")
    assertEqual(rows[0].name, rows[1].name, "两行的模型名相同（这就是用户看到的「一模一样」）")
    assertEqual(rows[0].tip == rows[1].tip, false, "同名模型的两行悬停文案必须不同")
    assertEqual(rows[0].tip.contains("ollama/deepseek-v4.1-flash"), true, "第一行悬停给出 ollama 全名")
    assertEqual(rows[1].tip.contains("open-design/deepseek-v4.1-flash"), true, "第二行悬停给出 open-design 全名")
    assertEqual(rows[0].tip.contains("open-design"), false, "第一行不串到另一个 provider")
    print("   · 同名模型样例一：" + rows[0].tip.replacingOccurrences(of: "\n", with: " ⏎ "))
    print("   · 同名模型样例二：" + rows[1].tip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

// MARK: - 项目行

private func testProjectRowTip() {
    let projects = [
        HarnessProjectUsage(path: "/Users/me/IdeaProjects/alpha", displayName: "alpha", sessionCount: 7,
                            usage: HarnessTokenUsage(uncachedInput: 300, requestCount: 3)),
        HarnessProjectUsage(path: "/Users/me/IdeaProjects/beta", displayName: "beta", sessionCount: 1,
                            usage: HarnessTokenUsage(uncachedInput: 100, requestCount: 1)),
    ]
    let rows = TokenDerive.projectRows(tokenSnapshot(projects: projects), window: .today)
    assertEqual(rows.count, 2, "两个项目两行")
    let tip = rows[0].tip
    assertEqual(tip.contains("alpha"), true, "项目行悬停文案含项目名")
    assertEqual(tip.contains("7 会话"), true, "项目行悬停文案含会话数")
    assertEqual(tip.contains(rows[0].amount), true, "项目行悬停文案含金额")
    assertEqual(tip.contains(TokenFormatting.percent(rows[0].share)), true, "项目行悬停文案含占比")
    assertEqual(tip.contains("provider"), false, "项目行没有 provider，不该出现 provider 字样")
    print("   · 项目行样例：" + tip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

// MARK: - 占比条整条

private func testStackBarTip() {
    let models = [
        HarnessModelUsage(provider: "ollama", model: "deepseek-v4.1-flash",
                          usage: HarnessTokenUsage(uncachedInput: 300, cacheRead: 100, requestCount: 1)),
        HarnessModelUsage(provider: "open-design", model: "deepseek-v4.1-flash",
                          usage: HarnessTokenUsage(uncachedInput: 100, cacheRead: 0, requestCount: 1)),
        HarnessModelUsage(provider: "", model: "local-model",
                          usage: HarnessTokenUsage(uncachedInput: 100, cacheRead: 0, requestCount: 1)),
    ]
    let rows = TokenDerive.modelRows(tokenSnapshot(models: models), window: .today)
    let tip = TokenDerive.stackBarTip(rows)
    let segments = tip.components(separatedBy: "\n")
    assertEqual(segments.count, rows.count, "占比条整条文案逐段：段数等于行数")
    assertEqual(segments[0].contains("ollama/deepseek-v4.1-flash"), true, "首段给出并列表 provider/model 全名")
    assertEqual(segments[1].contains("open-design/deepseek-v4.1-flash"), true, "次段是同名模型的另一个 provider")
    assertEqual(segments[2].hasPrefix("local-model"), true, "空 provider 的段落只写模型名")
    assertEqual(tip.contains("—"), false, "整条文案不出现破折号占位")
    for (index, row) in rows.enumerated() {
        assertEqual(segments[index].contains(row.amount), true, "第 \(index + 1) 段含该段金额")
        assertEqual(segments[index].contains(TokenFormatting.percent(row.share)), true,
                    "第 \(index + 1) 段含该段占比")
    }
    assertEqual(TokenDerive.stackBarTip([]), "", "无数据时整条文案为空（视图不挂 toolTip）")

    // 主面板条上只画前 6 段：被省略的行要有一句说明，避免误以为「就这么多」
    let partial = TokenDerive.stackBarTip(Array(rows.prefix(2)), hiddenCount: rows.count - 2)
    assertEqual(partial.contains("另有 1 个未画在条上"), true, "有条上未画出的行时给出数量说明")
    assertEqual(partial.components(separatedBy: "\n").count, 3, "两段 + 一行省略说明")
    assertEqual(TokenDerive.stackBarTip(rows, hiddenCount: 0).contains("另有"), false,
                "没有省略行时不出现「另有」")
    print("   · 占比条整条样例：" + tip.replacingOccurrences(of: "\n", with: " ⏎ "))
}

// MARK: - 分布行全名

private func testDistroRowFullName() {
    let plain = TokenDistroRow(rank: 1, name: "claude", provider: "anthropic",
                               sub: "", amount: "400", share: 0.4, colorIndex: 0, tip: "t")
    assertEqual(plain.fullName, "anthropic/claude", "provider 与模型不同名时拼成 provider/model")
    let sameName = TokenDistroRow(rank: 1, name: "ollama", provider: "ollama",
                                  sub: "", amount: "400", share: 0.4, colorIndex: 0)
    assertEqual(sameName.fullName, "ollama", "provider 与模型同名时不重复拼接")
    let noProvider = TokenDistroRow(rank: 1, name: "local", provider: "",
                                    sub: "", amount: "400", share: 0.4, colorIndex: 0)
    assertEqual(noProvider.fullName, "local", "provider 为空时不带斜杠")
    assertEqual(noProvider.tip, "", "未显式给 tip 时为空（DEBUG 取证构造的探针行不会挂到悬停上）")
    print("✅ 分布行全名（provider 空 / 同名 / 异名）works")
}

// MARK: - 无障碍文案（随范围，不写死「累计」）

/// 用户反馈的连带问题：「按项目 / 按模型」已跟随范围，但占比条与整卡的无障碍文案还写着「累计」
private func testDistroAccessibilityCopy() {
    for range in [TokenRange.today, .d7, .d30] {
        let barTip = TokenDistroDimension.projects.barAccessibility(range: range)
        assertEqual(barTip.contains("累计"), false, "\(range.title) 占比条无障碍文案不写死「累计」")
        assertEqual(barTip.contains(range.window.title), true,
                    "\(range.title) 占比条无障碍文案含当前范围「\(range.window.title)」")
        let cardTip = TokenDistroDimension.models.cardAccessibility(range: range)
        assertEqual(cardTip.contains("累计"), false, "\(range.title) 按模型卡无障碍文案不写死「累计」")
        assertEqual(cardTip.contains(range.window.title), true,
                    "\(range.title) 按模型卡无障碍文案含当前范围")
        assertEqual(cardTip.contains("按模型"), true, "按模型卡无障碍文案含维度名")
    }
    assertEqual(TokenDistroDimension.projects.barAccessibility(range: .today), "按项目 今日 占比条",
                "按项目占比条无障碍文案（今日）")
    assertEqual(TokenDistroDimension.models.barAccessibility(range: .d7), "按模型 近 7 天 占比条",
                "按模型占比条无障碍文案（近 7 天）")
    assertEqual(TokenDistroDimension.projects.cardAccessibility(range: .d30),
                "按项目 近 30 天分布，可点击查看项目明细", "按项目卡无障碍文案（近 30 天）")
    assertEqual(TokenDistroDimension.models.title, "按模型", "维度标题")
    print("✅ 分布卡 / 占比条无障碍文案随范围（不写死累计）works")
}
