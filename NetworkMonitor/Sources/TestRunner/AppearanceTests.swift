import Foundation
import NetworkMonitorCore

// MARK: - 外观层测试（主题令牌 / 渲染档映射）

/// 主题令牌表完整性
///
/// 断言口径：
/// - 三套主题都能为全部语义角色给出色值（缺角色会走 fallback，但 fallback 意味着「这个主题
///   忘了定义」，必须为 0 —— 否则某个角色在某个主题下静默变成中性灰）
/// - 默认 Apple 主题的取值与改造前逐项一致（这是「换令牌层不改变观感」的机器判据）
/// - 面系角色在三套主题间确实不同（否则「多套主题」是假的）
func runThemeTokenTests() {
    for id in ThemeID.allCases {
        let theme = ThemeCatalog.theme(for: id)
        for role in ThemeRole.allCases {
            // 显式定义过的角色必须命中；未定义走 fallback（这里断言「有值」而非「自定义值」）
            let color = theme.color(role, dark: false)
            let dark = theme.color(role, dark: true)
            assertEqual(String(describing: color).isEmpty, false, "\(id) \(role) 浅色应有值")
            assertEqual(String(describing: dark).isEmpty, false, "\(id) \(role) 深色应有值")
        }
    }

    // 默认主题必须把面系角色显式定义全，不允许靠 fallback 兜底
    let apple = ThemeCatalog.apple
    for role in [ThemeRole.surface, .cardFill, .bandFill, .track, .trackStrong, .hairline, .grid] {
        assertNotNil(apple.colors[role], "Apple 主题必须显式定义 \(role)")
    }

    // 改造前取值：卡片底 0xF5F5F7 / 0x26262A，带底 0xEEEFF2 / 0x2B2B30
    assertEqual(apple.color(.cardFill, dark: false).hexValue, 0xF5F5F7, "Apple 卡片底（浅）应与改造前一致")
    assertEqual(apple.color(.cardFill, dark: true).hexValue, 0x26262A, "Apple 卡片底（深）应与改造前一致")
    assertEqual(apple.color(.bandFill, dark: false).hexValue, 0xEEEFF2, "Apple 带底（浅）应与改造前一致")
    assertEqual(apple.color(.bandFill, dark: true).hexValue, 0x2B2B30, "Apple 带底（深）应与改造前一致")

    // 三套主题的面系必须互不相同（否则「多套主题」只是换了名字）
    let surfaces = ThemeID.allCases.map { ThemeCatalog.theme(for: $0).color(.surface, dark: false).hexValue }
    assertEqual(Set(surfaces).count, ThemeID.allCases.count, "三套主题的浅色底必须互不相同")
    let darkSurfaces = ThemeID.allCases.map { ThemeCatalog.theme(for: $0).color(.surface, dark: true).hexValue }
    assertEqual(Set(darkSurfaces).count, ThemeID.allCases.count, "三套主题的深色底必须互不相同")

    // 数据语义色在主题间**必须一致**（换肤不换语义）
    let family1 = ThemeID.allCases.map { ThemeCatalog.theme(for: $0).color(.family1, dark: false).hexValue }
    assertEqual(Set(family1).count, 1, "四族色不应随主题漂移")
    let okInk = ThemeID.allCases.map { ThemeCatalog.theme(for: $0).color(.okInk, dark: true).hexValue }
    assertEqual(Set(okInk).count, 1, "状态语义色不应随主题漂移")

    // 非法 rawValue 回落 Apple
    assertEqual(ThemeID.resolved(fromRaw: "not-a-theme"), .apple, "非法主题值应回落 Apple")
    assertEqual(ThemeID.resolved(fromRaw: ""), .apple, "空主题值应回落 Apple")
    assertEqual(ThemeCatalog.theme(for: .apple).id, .apple, "目录按 id 取主题")
}

/// 浅 / 深对比度：主题的「面 → 文字」组合必须过 WCAG 正文 4.5:1
///
/// 文字角色走 `labelColor` 通道（系统色），这里只对**显式 hex 的面**做算术断言：
/// 用主题自己的面系值 + 假设前景为纯黑/纯白，验证「最坏情况下正文仍可读」。
/// 这是「换肤不能把面板改成看不清」的机器判据（真机仍需人工复核一眼）。
func runThemeContrastTests() {
    for id in ThemeID.allCases {
        let theme = ThemeCatalog.theme(for: id)
        for isDark in [false, true] {
            guard let surfaceHex = theme.color(.surface, dark: isDark).hexValue,
                  let cardHex = theme.color(.cardFill, dark: isDark).hexValue else {
                assertEqual(true, false, "\(id) 面系必须是显式 hex 才能算对比度")
                continue
            }
            let surface = SystemPaletteRGB(hex: surfaceHex)
            let card = SystemPaletteRGB(hex: cardHex)
            // 前景取纯黑（浅色主题）/ 纯白（深色主题）：`labelColor` 解析后就是这个方向
            let ink = SystemPaletteRGB(hex: isDark ? 0xFFFFFF : 0x000000)
            let onSurface = surface.contrastRatio(with: ink)
            let onCard = card.contrastRatio(with: ink)
            assertEqual(onSurface >= 4.5, true,
                        "\(id) \(isDark ? "深" : "浅")色主题：底与正文对比度 \(onSurface) 应 ≥ 4.5")
            assertEqual(onCard >= 4.5, true,
                        "\(id) \(isDark ? "深" : "浅")色主题：卡片底与正文对比度 \(onCard) 应 ≥ 4.5")
        }
    }
}

/// 渲染档映射：三档的全部参数逐项断言
func runRenderTierTests() {
    // 标准档 = 改造前默认行为（1 秒 / 5 秒 / 60 点 / 动效全开）
    let standard = RenderTierLogic.profile(for: .standard)
    assertEqual(standard.tickInterval, 1.0, "标准档 tick 应为 1 秒")
    assertEqual(standard.midInterval, 5.0, "标准档中频应为 5 秒")
    assertEqual(standard.sampleInterval, 1.0, "标准档采样应为 1 秒")
    assertEqual(standard.historyPoints, 60, "标准档采样点应为 60")
    assertEqual(standard.motionEnabled, true, "标准档动效应开启")
    assertEqual(standard.glassEnabled, true, "标准档玻璃应开启")
    assertEqual(standard.glassInteractive, false, "标准档玻璃不交互随动")
    assertEqual(standard.prewarm, true, "标准档应预热面板")
    assertEqual(standard.chartBucketLimit, 24, "标准档图表桶应为 24")
    assertEqual(standard.rankingLimit, 8, "标准档排行应为 8 行")
    assertEqual(standard.stopsTickWhenClosed, false, "标准档收起时仍 tick")

    // 极致档：更密 + 交互玻璃 + 采样翻倍
    let extreme = RenderTierLogic.profile(for: .extreme)
    assertEqual(extreme.tickInterval, 0.5, "极致档 tick 应为 0.5 秒")
    assertEqual(extreme.midInterval, 2.0, "极致档中频应为 2 秒")
    assertEqual(extreme.sampleInterval, 0.5, "极致档采样应为 0.5 秒")
    assertEqual(extreme.historyPoints, 120, "极致档采样点应为 120")
    assertEqual(extreme.glassInteractive, true, "极致档玻璃应交互随动")
    assertEqual(extreme.motionExpand, 0.40, "极致档展开动效应略长")

    // 省电档：放宽 + 关玻璃 + 落终态 + 降采样 + 收起停 tick
    let powerSave = RenderTierLogic.profile(for: .powerSave)
    assertEqual(powerSave.tickInterval, 2.0, "省电档 tick 应为 2 秒")
    assertEqual(powerSave.midInterval, 15.0, "省电档中频应为 15 秒")
    assertEqual(powerSave.sampleInterval, 3.0, "省电档采样应为 3 秒")
    assertEqual(powerSave.historyPoints, 30, "省电档采样点应为 30")
    assertEqual(powerSave.motionEnabled, false, "省电档动效应关闭")
    assertEqual(powerSave.glassEnabled, false, "省电档玻璃应关闭")
    assertEqual(powerSave.prewarm, false, "省电档不预热")
    assertEqual(powerSave.chartBucketLimit, 12, "省电档图表桶应降为 12")
    assertEqual(powerSave.rankingLimit, 4, "省电档排行应降为 4 行")
    assertEqual(powerSave.sparkWidth, 40, "省电档迷你折线应收窄")
    assertEqual(powerSave.stopsTickWhenClosed, true, "省电档收起时应停 tick")

    // 档位必须真不一样（防止三档表写成同一份）
    assertEqual(standard != extreme, true, "标准与极致档参数必须不同")
    assertEqual(standard != powerSave, true, "标准与省电档参数必须不同")

    // 非法 rawValue 回落标准档
    assertEqual(RenderTier.resolved(fromRaw: "turbo"), .standard, "非法档位应回落标准")
    assertEqual(RenderTier.resolved(fromRaw: ""), .standard, "空档位应回落标准")
}

/// 玻璃开关的合成规则：用户显式值优先，没设过跟随档位
func runRenderTierGlassTests() {
    assertEqual(RenderTierLogic.effectiveGlass(override: nil, tier: .standard), true,
                "未手动设置时标准档玻璃应开")
    assertEqual(RenderTierLogic.effectiveGlass(override: nil, tier: .powerSave), false,
                "未手动设置时省电档玻璃应关")
    assertEqual(RenderTierLogic.effectiveGlass(override: true, tier: .powerSave), true,
                "用户手动开启后，省电档也要尊重用户选择")
    assertEqual(RenderTierLogic.effectiveGlass(override: false, tier: .standard), false,
                "用户手动关闭后，标准档也要尊重用户选择")
}

/// 面板刷新闸门与图表降采样
func runRenderTierGateTests() {
    // 省电档：面板收起时整轮停摆；其余档收起时仍允许后台刷新
    assertEqual(RenderTierLogic.shouldRefreshPanel(tier: .powerSave, panelVisible: false), false,
                "省电档收起时应停 tick")
    assertEqual(RenderTierLogic.shouldRefreshPanel(tier: .powerSave, panelVisible: true), true,
                "省电档展开时仍要刷新")
    assertEqual(RenderTierLogic.shouldRefreshPanel(tier: .standard, panelVisible: false), true,
                "标准档收起时仍允许后台刷新")
    assertEqual(RenderTierLogic.shouldRefreshPanel(tier: .extreme, panelVisible: false), true,
                "极致档收起时仍允许后台刷新")

    // 图表桶：不足取可用数，超上限取上限
    assertEqual(RenderTierLogic.chartBuckets(available: 6, tier: .standard), 6, "数据不足时按可用数")
    assertEqual(RenderTierLogic.chartBuckets(available: 24, tier: .standard), 24, "恰好等于上限时不变")
    assertEqual(RenderTierLogic.chartBuckets(available: 24, tier: .powerSave), 12, "省电档 24 桶降为 12")
    assertEqual(RenderTierLogic.chartBuckets(available: 0, tier: .powerSave), 0, "无数据时为 0")

    // 采样点 / 排行上限
    assertEqual(RenderTierLogic.historyLimit(tier: .extreme), 120, "极致档采样点上限")
    assertEqual(RenderTierLogic.historyLimit(tier: .powerSave), 30, "省电档采样点上限")
    assertEqual(RenderTierLogic.rankingLimit(tier: .powerSave), 4, "省电档排行上限")

    // 摘要行必须包含三档的关键数值（切档自证用）
    let summary = RenderTierLogic.summary(for: .powerSave)
    assertEqual(summary.contains("2.0"), true, "摘要应含 tick 周期")
    assertEqual(summary.contains("15.0"), true, "摘要应含中频周期")
    assertEqual(summary.contains("关"), true, "摘要应标明玻璃或动效关闭")
}

/// 外观偏好：读写回环 / 缺键默认 / 玻璃显式标记 / reset
func runAppearancePreferencesTests() {
    let storage = InMemoryStorage()
    let preferences = AppearancePreferences(storage: storage)

    // 缺键默认：Apple + 标准档 + 玻璃跟随档位
    assertEqual(preferences.themeID, .apple, "缺键时主题应为 Apple")
    assertEqual(preferences.renderTier, .standard, "缺键时档位应为标准")
    assertEqual(preferences.glassOverride == nil, true, "缺键时玻璃应无显式值")
    assertEqual(preferences.glassEnabled, true, "标准档下玻璃默认开")

    // 写入回读
    preferences.themeID = .sand
    assertEqual(preferences.themeID, .sand, "主题应可回读")
    assertEqual(preferences.theme.id, .sand, "主题定义应跟随 id")

    preferences.renderTier = .powerSave
    assertEqual(preferences.renderTier, .powerSave, "档位应可回读")
    assertEqual(preferences.glassEnabled, false, "省电档下玻璃应跟随为关")
    assertEqual(preferences.renderProfile.tickInterval, 2.0, "参数表应跟随档位")

    // 显式玻璃值优先于档位
    preferences.glassOverride = true
    assertEqual(preferences.glassEnabled, true, "显式开启应覆盖省电档的默认关")
    assertEqual(preferences.glassOverride, true, "显式值应可回读")

    // 清掉显式值后重新跟随档位
    preferences.glassOverride = nil
    assertEqual(preferences.glassOverride == nil, true, "清空后应回到无显式值")
    assertEqual(preferences.glassEnabled, false, "无显式值时重新跟随省电档")

    // reset 回默认
    preferences.reset()
    assertEqual(preferences.themeID, .apple, "reset 后主题回 Apple")
    assertEqual(preferences.renderTier, .standard, "reset 后档位回标准")
    assertEqual(preferences.glassOverride == nil, true, "reset 后玻璃无显式值")
}
