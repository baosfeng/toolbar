import Foundation
import NetworkMonitorCore

// MARK: - 来源 App 主题色（纯值 · 不依赖 AppKit）

/// 剪贴板卡片头带按来源 App 染色 —— 色表、取色与对比度计算都在这里，视图只取结果
///
/// 匹配口径（与白名单同源，不做模糊推断）：
/// 1. bundleID 精确命中（大小写不敏感）；
/// 2. App 名与别名全等命中（同样大小写不敏感）；
/// 3. 都没命中回落主题带底色（`ThemeRole.bandFill` 浅色档），未知来源不会得到一块花色。
public enum SourceAppPalette {

    /// 一个受支持的来源：bundleID + App 名别名 + 主题色
    public struct Source: Equatable, Sendable {
        /// 精确匹配用的 bundleID
        public let bundleID: String
        /// App 名别名（小写比较，中英文都列）
        public let aliases: [String]
        /// 头带底色
        public let color: SystemPaletteRGB

        public init(bundleID: String, aliases: [String], hex: UInt32) {
            self.bundleID = bundleID
            self.aliases = aliases
            self.color = SystemPaletteRGB(hex: hex)
        }
    }

    /// 头带取色结果
    public struct Tint: Equatable, Sendable {
        /// 头带底色
        public let color: SystemPaletteRGB
        /// 是否回落（true = 没命中任何内置来源）
        public let isFallback: Bool
    }

    /// 头带墨色（黑 / 白二选一）与它的对比度
    public struct Ink: Equatable, Sendable {
        /// 头部文字色
        public let color: SystemPaletteRGB
        /// 文字色与头带底色的对比度（1…21）
        public let ratio: Double
    }

    /// 内置来源表
    ///
    /// 白名单显式列举：不做「名字里含 safari 就算」的模糊匹配——那会把
    /// 「Safari 技术预览」这类外来进程一并染色，且新 App 上线时会静默变色。
    public static let sources: [Source] = [
        Source(bundleID: "com.apple.Safari", aliases: ["safari"], hex: 0x0068D9),
        Source(bundleID: "com.tencent.xinWeChat", aliases: ["wechat", "微信"], hex: 0x07C160),
        Source(bundleID: "com.apple.dt.Xcode", aliases: ["xcode"], hex: 0x147EFB),
        Source(bundleID: "notion.id", aliases: ["notion"], hex: 0x2F3437),
        Source(bundleID: "com.figma.Desktop", aliases: ["figma"], hex: 0xF24E1E),
        Source(bundleID: "com.apple.Terminal", aliases: ["terminal", "终端"], hex: 0x1C1C1E),
        Source(bundleID: "com.google.Chrome", aliases: ["chrome", "google chrome"], hex: 0x8CC63F),
        Source(bundleID: "com.microsoft.VSCode",
               aliases: ["vs code", "visual studio code", "code"], hex: 0x007ACC),
        Source(bundleID: "com.apple.finder", aliases: ["finder", "访达"], hex: 0x2C7DF0),
    ]

    /// 墨色候选（纯黑 / 纯白，sRGB）
    public static let inkBlack = SystemPaletteRGB(hex: 0x000000)
    /// 墨色候选（纯白）
    public static let inkWhite = SystemPaletteRGB(hex: 0xFFFFFF)

    /// 未知来源的回落带底色 — 固定中性灰，不取主题 `bandFill`
    ///
    /// 为什么不用主题带底色：卡头带落在**卡片面**（`cardFill`）上，而主题的 `bandFill`
    /// 与 `cardFill` 只差 5% 左右（Apple 浅色 `0xEEEFF2` on `0xF5F5F7` 只有 1.06:1），
    /// 画上去看不出「这里有一条带」，卡片的头 / 身分界会消失。这里取一档与三套主题的卡面
    /// 都拉开 ≥1.2:1 的中性灰（`ClipboardHeadBandContrastTests` 逐主题 × 浅深守住）。
    public static func fallbackColor(isDark: Bool) -> SystemPaletteRGB {
        SystemPaletteRGB(hex: isDark ? 0x3A3A40 : 0xD8D8DD)
    }

    // MARK: 取色

    /// 来源 → 头带底色；入参全空按未知来源回落
    ///
    /// 未定义行为按回落处理（不抛异常、不返回 nil）：卡片头带是装饰，
    /// 宁可退成中性带底，也不能因为一条脏数据让整张卡画不出来。
    public static func tint(bundleID: String?, appName: String?, isDark: Bool = false) -> Tint {
        let bundle = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !bundle.isEmpty,
           let hit = sources.first(where: { $0.bundleID.lowercased() == bundle }) {
            return Tint(color: hit.color, isFallback: false)
        }
        if !name.isEmpty,
           let hit = sources.first(where: { $0.aliases.contains(name) }) {
            return Tint(color: hit.color, isFallback: false)
        }
        return Tint(color: fallbackColor(isDark: isDark), isFallback: true)
    }

    // MARK: 对比度

    /// WCAG 2.1 对比度（前景 / 背景，1…21，与参数顺序无关）
    public static func contrastRatio(_ foreground: SystemPaletteRGB,
                                     _ background: SystemPaletteRGB) -> Double {
        foreground.contrastRatio(with: background)
    }

    /// 头带文字取黑还是白 —— 取对比度更高的一档
    ///
    /// 两档都达不到 WCAG AA 4.5:1 时仍取较高的那一档：头带是装饰元素，
    /// 宁可对比度偏弱，也不把文字刷成第三色破坏「非黑即白」的观感。
    /// 内置来源色的色值已按「至少一档 ≥ 4.5:1」挑过，用例守住这条。
    public static func ink(on background: SystemPaletteRGB) -> Ink {
        let black = contrastRatio(inkBlack, background)
        let white = contrastRatio(inkWhite, background)
        return black >= white ? Ink(color: inkBlack, ratio: black)
                              : Ink(color: inkWhite, ratio: white)
    }
}