import Foundation

// MARK: - 主题目录（三套主题的唯一注册表）

/// 主题目录 — 全部主题定义在这里，界面层只按 `ThemeID` 取，不各页自造色
///
/// 设计裁决（两条，都有理由）：
///
/// 1. **换肤换壳、不换数据语义**：四族色（未缓存蓝 / 缓存读青绿 / 输出靛 / 请求橙）、
///    状态语义色（达标绿 / 告警琥珀 / 占位灰 / 缓存堆叠）与文字角色在三套主题间**完全共用**。
///    理由：这四族是「数据含义」的载体，同屏并排出现，颜色一漂移用户就要重新学一遍；
///    系统页指标族（CPU 蓝 / GPU 靛 / 内存青绿 / 压力橙 / 磁盘石墨）同理，继续由
///    `SystemPaletteTokens` 独占。主题只改**面、线、轨道、着色与玻璃**。
/// 2. **文字用系统色通道**（`.label(alpha)`）而不是写死 hex：现网文字是 `labelColor`
///    按 88% / 62% 派生的，换成固定 hex 会在深色下改变观感与对比度（面板 282pt 内宽
///    跑的是 10.5pt 小字，历史上已经因为对比度不足被打回过一次）。
public enum ThemeCatalog {

    /// 全部主题（顺序即设置页下拉顺序）
    public static let all: [Theme] = [apple, graphite, sand]

    /// 按 id 取主题；未知 id 回落 Apple
    public static func theme(for id: ThemeID) -> Theme {
        all.first { $0.id == id } ?? apple
    }

    // MARK: - 共用角色（三套主题共享，换肤不动数据语义）

    /// 三套主题完全共用的角色表
    static let sharedRoles: [ThemeRole: ThemeColorPair] = [
        // 文字（走系统色通道，对比度由系统保证）
        .textPrimary: ThemeColorPair(light: .label(1), dark: .label(1)),
        .textSecondary: ThemeColorPair(light: .label(0.88), dark: .label(0.88)),
        .textTertiary: ThemeColorPair(light: .label(0.62), dark: .label(0.62)),
        .accent: ThemeColorPair(light: .systemAccent, dark: .systemAccent),
        .selectedFill: ThemeColorPair(light: .label(0.07), dark: .label(0.07)),

        // 四族：未缓存（蓝）
        .family1: ThemeColorPair(light: .hex(0x0071E3), dark: .hex(0x409CFF)),
        .family1Ink: ThemeColorPair(light: .hex(0x0058B3), dark: .hex(0x6FB6FF)),
        .family1Fill: ThemeColorPair(light: .hex(0xEBF1FA), dark: .hex(0x262E39)),
        // 四族：缓存读（青绿）
        .family2: ThemeColorPair(light: .hex(0x0D9488), dark: .hex(0x2DD4BF)),
        .family2Ink: ThemeColorPair(light: .hex(0x0B6D64), dark: .hex(0x5CE3D2)),
        .family2Fill: ThemeColorPair(light: .hex(0xE9F2F1), dark: .hex(0x243130)),
        // 四族：输出（靛）
        .family3: ThemeColorPair(light: .hex(0x5B5BD6), dark: .hex(0xA89DFF)),
        .family3Ink: ThemeColorPair(light: .hex(0x4A44B8), dark: .hex(0xBFB6FF)),
        .family3Fill: ThemeColorPair(light: .hex(0xEEEDF8), dark: .hex(0x2D2B39)),
        // 四族：请求（橙）
        .family4: ThemeColorPair(light: .hex(0xC2410C), dark: .hex(0xFF8A4C)),
        .family4Ink: ThemeColorPair(light: .hex(0xA83A0B), dark: .hex(0xFFAB7D)),
        .family4Fill: ThemeColorPair(light: .hex(0xF8EFEB), dark: .hex(0x332C27)),

        // 状态语义
        .ok: ThemeColorPair(light: .hex(0x14913F), dark: .hex(0x34D399)),
        .okInk: ThemeColorPair(light: .hex(0x116F33), dark: .hex(0x6EE7B7)),
        .warnInk: ThemeColorPair(light: .hex(0x8A5A06), dark: .hex(0xF0CF82)),
        .ghost: ThemeColorPair(light: .hex(0xB4B4BE), dark: .hex(0x6A6A72)),
        .cacheStack: ThemeColorPair(light: .hex(0x8FC7C3), dark: .hex(0x2C6B65)),

        // 卡片描边 / 高光（玻璃三件套的后两件，三套共用同一强度）
        .cardStroke: ThemeColorPair(light: .label(0.10), dark: .label(0.10)),
        .cardHighlight: ThemeColorPair(light: .white(0.55), dark: .white(0.12)),
    ]

    // MARK: - 默认主题 Apple（原值原样，装上就是零变化）

    /// 默认主题 —— 各角色的取值与改造前逐项一致，保证「换到新令牌层不改变观感」
    public static let apple: Theme = Theme(
        id: .apple,
        displayName: ThemeID.apple.displayName,
        detail: ThemeID.apple.detail,
        colors: sharedRoles.merging(surfaceRoles(
            surface: (0xFFFFFF, 0x1A1A1C),
            cardFill: (0xF5F5F7, 0x26262A),
            bandFill: (0xEEEFF2, 0x2B2B30),
            track: (0xE4E4EA, 0x39393F),
            trackStrong: (0xD6D6DE, 0x43434A),
            hairline: (0xE8E8ED, 0x313136),
            grid: (0xECECF1, 0x3A3A40),
            panelTint: (0x000000, 0x000000)
        )) { $1 },
        material: ThemeMaterialRecipe(style: .regular,
                                      cardFillAlpha: 0.72,
                                      highlightAlpha: 0.55,
                                      strokeAlpha: 0.10,
                                      panelTintAlpha: 0),
        shadow: ThemeShadowRecipe(radius: 18, offsetY: -6, opacity: 0.18)
    )

    // MARK: - 冷调石墨（蓝灰面、低饱和）

    /// 冷调石墨 —— 面系转向蓝灰，四族与文字不动
    public static let graphite: Theme = Theme(
        id: .graphite,
        displayName: ThemeID.graphite.displayName,
        detail: ThemeID.graphite.detail,
        colors: sharedRoles.merging(surfaceRoles(
            surface: (0xF1F4F8, 0x14161A),
            cardFill: (0xECF0F6, 0x1E2229),
            bandFill: (0xE2E8F1, 0x242932),
            track: (0xD8DFE9, 0x2F3641),
            trackStrong: (0xC6CEDB, 0x3B4351),
            hairline: (0xDCE3ED, 0x2B313B),
            grid: (0xE3E9F2, 0x313842),
            panelTint: (0x1F3A5F, 0x5C86C4)
        )) { $1 },
        material: ThemeMaterialRecipe(style: .regular,
                                      cardFillAlpha: 0.68,
                                      highlightAlpha: 0.48,
                                      strokeAlpha: 0.12,
                                      panelTintAlpha: 0.06),
        shadow: ThemeShadowRecipe(radius: 18, offsetY: -6, opacity: 0.20)
    )

    // MARK: - 暖调米白（米色面、暖灰描边）

    /// 暖调米白 —— 面系转向暖白，四族与文字不动
    public static let sand: Theme = Theme(
        id: .sand,
        displayName: ThemeID.sand.displayName,
        detail: ThemeID.sand.detail,
        colors: sharedRoles.merging(surfaceRoles(
            surface: (0xFCF8F1, 0x1A1714),
            cardFill: (0xF8F3EA, 0x26221D),
            bandFill: (0xF0E9DD, 0x2D2822),
            track: (0xE6DFD2, 0x39332B),
            trackStrong: (0xD7CEBE, 0x464035),
            hairline: (0xE9E2D5, 0x332E28),
            grid: (0xF0E9DC, 0x3A342D),
            panelTint: (0x9A6B2E, 0xE3C089)
        )) { $1 },
        material: ThemeMaterialRecipe(style: .regular,
                                      cardFillAlpha: 0.70,
                                      highlightAlpha: 0.52,
                                      strokeAlpha: 0.12,
                                      panelTintAlpha: 0.05),
        shadow: ThemeShadowRecipe(radius: 18, offsetY: -6, opacity: 0.18)
    )

    // MARK: - 面系角色装配

    /// 面系角色（三套主题各自定义的那一组）— 只描述「壳」，不碰四族与文字
    ///
    /// - Parameters:
    ///   - 每个参数都是 `(浅色 hex, 深色 hex)` 二元组，顺序固定好读
    static func surfaceRoles(
        surface: (UInt32, UInt32),
        cardFill: (UInt32, UInt32),
        bandFill: (UInt32, UInt32),
        track: (UInt32, UInt32),
        trackStrong: (UInt32, UInt32),
        hairline: (UInt32, UInt32),
        grid: (UInt32, UInt32),
        panelTint: (UInt32, UInt32)
    ) -> [ThemeRole: ThemeColorPair] {
        func pair(_ tuple: (UInt32, UInt32)) -> ThemeColorPair {
            ThemeColorPair(light: .hex(tuple.0), dark: .hex(tuple.1))
        }
        return [
            .surface: pair(surface),
            .cardFill: pair(cardFill),
            .bandFill: pair(bandFill),
            .track: pair(track),
            .trackStrong: pair(trackStrong),
            .hairline: pair(hairline),
            .grid: pair(grid),
            .panelTint: pair(panelTint),
        ]
    }
}
