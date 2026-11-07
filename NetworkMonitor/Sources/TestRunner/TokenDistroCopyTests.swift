import Foundation
import NetworkMonitorCore

// MARK: - Token 二级页（按项目 / 按模型）范围口径文案测试
//
// 从 TokenRangeConsistencyTests.swift 拆出：那边已到 347 行 / 21.7 KB，超过单文件门禁阈值。
// 本文件只覆盖「二级页文案随范围」，由 runTokenRangeConsistencyTests() 调用（不影响 main.swift 调度）。

// MARK: - 二级页范围文案（Core 派生，视图只透传）

/// 二级页「按项目 / 按模型」的面包屑 meta、Hero 副标题、说明卡都必须说当前范围。
///
/// 曾经这几处写死「累计口径」「不能按今日 / 近 7 天过滤」「项目维度只有累计口径」，
/// 而主面板两张卡早就在跟随范围 —— 同一屏两套说法，用户直接抱怨数据对不上。
/// 文案在 Core（TokenDerive.distroCopy）派生，这里对文案本身下断言，视图里拼字符串就测不到了。
/// 跨文件访问：由 TokenRangeConsistencyTests.swift 的套件入口调用，private 放宽为 internal
func testDistroPageCopyFollowsRange() {
    // 三档窗口给不同数据：今日 1 个项目 / 7 天 2 个 / 30 天 3 个，方便断言「换范围就换数据」
    let alpha = HarnessProjectUsage(path: "/tmp/alpha", displayName: "alpha", sessionCount: 1,
                                    usage: HarnessTokenUsage(uncachedInput: 1_000, requestCount: 1))
    let beta = HarnessProjectUsage(path: "/tmp/beta", displayName: "beta", sessionCount: 2,
                                   usage: HarnessTokenUsage(uncachedInput: 2_000, requestCount: 2))
    let gamma = HarnessProjectUsage(path: "/tmp/gamma", displayName: "gamma", sessionCount: 3,
                                    usage: HarnessTokenUsage(uncachedInput: 3_000, requestCount: 3))
    let modelA = HarnessModelUsage(provider: "deepseek", model: "v4",
                                   usage: HarnessTokenUsage(uncachedInput: 1_000, cacheRead: 1_000, requestCount: 1))
    let modelB = HarnessModelUsage(provider: "ollama", model: "qwen",
                                   usage: HarnessTokenUsage(uncachedInput: 2_000, requestCount: 2))
    let modelC = HarnessModelUsage(provider: "open-design", model: "flash",
                                   usage: HarnessTokenUsage(uncachedInput: 3_000, requestCount: 3))

    let snapshot = HarnessUsageSnapshot(
        totals: HarnessUsageTotals(today: .zero, thisWeek: .zero, allTime: .zero, cacheHitRate: nil),
        daily: [],
        projects: [alpha, beta, gamma],
        models: [modelA, modelB, modelC],
        windowedProjects: [.today: [alpha], .last7Days: [beta, alpha], .last30Days: [gamma, beta, alpha]],
        windowedModels: [.today: [modelA], .last7Days: [modelB, modelA], .last30Days: [modelC, modelB, modelA]],
        windowProjectTotals: [.today: alpha.usage,
                              .last7Days: alpha.usage.adding(beta.usage),
                              .last30Days: alpha.usage.adding(beta.usage).adding(gamma.usage)],
        windowModelTotals: [.today: modelA.usage,
                            .last7Days: modelA.usage.adding(modelB.usage),
                            .last30Days: modelA.usage.adding(modelB.usage).adding(modelC.usage)],
        indexedSessions: 3, totalSessions: 3, lastScanAt: nil,
        indexingState: .ready, sourceAvailability: .available(toolPath: "/usr/local/bin/zstd"))

    // 同一份 snapshot 三个范围各建一次模型
    func paneModel(_ range: TokenRange) -> TokenPaneModel {
        TokenPaneModel.make(snapshot: snapshot, range: range, hourScope: .today,
                            hourView: .stack, metric: .total, trendMode: .stack)
    }
    let today = paneModel(.today)
    let d7 = paneModel(.d7)
    let d30 = paneModel(.d30)

    // 1) 行内容随范围变化（不只是数量）
    assertEqual(today.projects.map(\.name), ["alpha"], "今日按项目只有 alpha")
    assertEqual(d7.projects.map(\.name), ["beta", "alpha"], "近 7 天按项目两行且按 tok 降序")
    assertEqual(d30.projects.map(\.name), ["gamma", "beta", "alpha"], "近 30 天按项目三行")
    assertEqual(today.models.map(\.name), ["v4"], "今日按模型只有 v4")
    assertEqual(d30.models.map(\.name), ["flash", "qwen", "v4"], "近 30 天按模型三行")
    assertEqual(today.projects.first?.amount != d30.projects.first?.amount, true,
                "今日与近 30 天首位金额不同（换范围换数据，不是换标签）")
    assertEqual(today.models.first?.sub != d7.models.first?.sub, true,
                "今日与近 7 天模型行说明不同（占比/命中率按各自窗口算）")

    // 2) 二级页面包屑 meta 随范围变化，且不再出现「累计口径」
    assertEqual(today.distroCopy.projectsCrumbMeta, "今日口径", "今日范围：按项目面包屑 meta")
    assertEqual(d7.distroCopy.projectsCrumbMeta, "近 7 天口径", "近 7 天范围：按项目面包屑 meta")
    assertEqual(d30.distroCopy.modelsCrumbMeta, "近 30 天口径", "近 30 天范围：按模型面包屑 meta")
    for model in [today, d7, d30] {
        let title = model.range.title
        assertEqual(model.distroCopy.rangeTitle, title, "\(title) 范围名透出给二级页")
        // 面包屑 meta / Hero 副标题 / 说明卡一律跟随范围，且没有任何「累计」类旧口径
        let texts = [model.distroCopy.projectsCrumbMeta, model.distroCopy.modelsCrumbMeta,
                     model.distroCopy.projectsHeroSub, model.distroCopy.modelsHeroSub,
                     model.distroCopy.projectsNote, model.distroCopy.modelsNote,
                     model.distroCopy.projectsBarAccessibility, model.distroCopy.modelsBarAccessibility,
                     model.distroCopy.hitCardMeta]
        assertEqual(texts.allSatisfy { $0.contains(title) }, true, "\(title) 二级页各处文案都标了当前范围")
        assertEqual(texts.allSatisfy { !$0.contains("累计") }, true,
                    "\(title) 二级页文案不再出现「累计」类旧口径")
        assertEqual(texts.allSatisfy { !$0.contains("不能按今日") }, true,
                    "\(title) 二级页文案不再出现「不能按今日过滤」")
    }
    assertEqual(Set([today.distroCopy.modelsNote, d7.distroCopy.modelsNote, d30.distroCopy.modelsNote]).count, 3,
                "三档范围的模型说明卡文案互不相同")

    // 3) 说明卡必须写清「跟随主面板范围」与「分母是该窗口全部合计」
    for model in [today, d7, d30] {
        assertEqual(model.distroCopy.projectsNote.contains("跟随主面板范围"), true,
                    "项目说明卡声明跟随主面板范围")
        assertEqual(model.distroCopy.projectsNote.contains("占比分母是该窗口内全部项目的合计"), true,
                    "项目说明卡写清占比分母口径（与该窗口全部项目合计一致）")
        assertEqual(model.distroCopy.modelsNote.contains("跟随主面板范围"), true,
                    "模型说明卡声明跟随主面板范围")
        assertEqual(model.distroCopy.modelsNote.contains("占比分母是该窗口内全部模型的合计"), true,
                    "模型说明卡写清占比分母口径")
    }

    // 4) 主面板卡头与二级页文案同源（同一个 rangeTitle），不会一处跟随一处累计
    assertEqual(today.projectMeta, "\(today.distroCopy.rangeTitle) \(today.projects.count) 个",
                "主面板卡头与二级页文案同源（今日）")
    assertEqual(d30.modelMeta, "\(d30.distroCopy.rangeTitle) \(d30.models.count) 个",
                "主面板卡头与二级页文案同源（近 30 天）")

    // 5) 缓存命中页：说明必须与实现一致（逐桶取 todayBuckets，固定今日 24 桶）
    let cacheNote = TokenDistroCopy.cacheNote
    assertEqual(cacheNote.contains("逐桶命中率跟随主面板范围"), false,
                "缓存命中页说明不再声称逐桶命中率跟随主面板范围（实现固定今日 24 桶）")
    assertEqual(cacheNote.contains("不随主面板范围切换"), true,
                "缓存命中页说明写清三块都不随主面板范围切换")
    assertEqual(cacheNote.contains("逐桶命中率固定今日 24 桶"), true,
                "缓存命中页说明与 todayBuckets 的实现一致")
    assertEqual(cacheNote.contains("走势与均值固定 30 天"), true,
                "缓存命中页说明写清走势与均值固定 30 天")
    assertEqual(cacheNote.contains("主数值取今日"), true,
                "缓存命中页说明写清主数值取今日")
    assertEqual(cacheNote.contains("输出不进分母"), true,
                "缓存命中页说明保留「输出不进分母」口径")

    // 6) 单桶（历史日）详情页的说明也不再声称「项目与模型仍是累计口径」
    assertEqual(TokenDistroCopy.dayBucketNote.contains("累计"), false,
                "历史日详情说明不再写「累计口径」")
    assertEqual(TokenDistroCopy.dayBucketNote.contains("跟随主面板范围"), true,
                "历史日详情说明改为声明跟随主面板范围")
    print("✅ Token 二级页范围文案（面包屑 / Hero / 说明卡随范围，无「累计口径」残留）works")
}

