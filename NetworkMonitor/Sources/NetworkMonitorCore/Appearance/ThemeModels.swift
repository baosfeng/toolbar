import Foundation

// MARK: - 主题模型（纯值 · 不依赖 AppKit）

/// 主题标识 — 每套主题提供浅 / 深两套语义色，深色与浅色同级（都是一等公民）
///
/// 分层关系（重要）：本类型只描述**界面壳层**（面板底、卡片面、轨道、线、四族色、状态语义色）。
/// 系统页的**指标族**色（CPU 蓝 / GPU 靛 / 内存青绿 / 压力橙 / 磁盘石墨 / Wi-Fi / 电量 / 温度）
/// 仍由 `SystemPaletteTokens` 独占：那是「数据语义」不是「皮肤」，v3 定稿后不随主题漂移。
public enum ThemeID: String, CaseIterable, Sendable {
    case apple
    case graphite
    case sand

    /// 设置页下拉标题
    public var displayName: String {
        switch self {
        case .apple: return "Apple"
        case .graphite: return "冷调石墨"
        case .sand: return "暖调米白"
        }
    }

    /// 设置页一句话说明
    public var detail: String {
        switch self {
        case .apple: return "跟随系统本身的中性灰面，默认档。"
        case .graphite: return "面向深色偏冷的中性面，蓝灰底色、更低饱和。"
        case .sand: return "面向暖白的中性面，米色底、暖灰描边。"
        }
    }

    /// rawValue → 主题；非法值回落 Apple（偏好里存了旧版本残留值时不炸）
    public static func resolved(fromRaw raw: String) -> ThemeID {
        ThemeID(rawValue: raw) ?? .apple
    }
}

/// 语义色角色 — 界面壳层唯一取色入口
///
/// 命名按「用在哪」而不是「是什么颜色」：换主题只改色值，调用点不动。
public enum ThemeRole: String, CaseIterable, Sendable {
    // MARK: 底与面
    /// 面板 / 窗口页底
    case surface
    /// 面板叠加着色（叠在系统 windowBackgroundColor 之上，alpha 由主题材质配方给）
    case panelTint
    /// 卡片实色面
    case cardFill
    /// 状态带 / 胶囊底
    case bandFill
    /// 图表轨道（未填充段）
    case track
    /// 强轨道（分布条剩余段 / 柱底）
    case trackStrong

    // MARK: 线与网格
    /// 1pt 分隔线
    case hairline
    /// 图表网格线
    case grid
    /// 选中态 / 悬停浅底
    case selectedFill

    // MARK: 文字
    /// 主文字
    case textPrimary
    /// 次要文字（10.5pt 行名等，需 ≥ 4.5:1）
    case textSecondary
    /// 三级文字（8.5–10pt 图表坐标）
    case textTertiary
    /// 强调色（分段选中 / 链接）
    case accent

    // MARK: 四族（Token 页：未缓存 / 缓存读 / 输出 / 请求）
    case family1, family1Ink, family1Fill
    case family2, family2Ink, family2Fill
    case family3, family3Ink, family3Fill
    case family4, family4Ink, family4Fill

    // MARK: 状态语义
    /// 达标主色（进度条正常段）
    case ok
    /// 达标墨色（文字）
    case okInk
    /// 告警墨色（额度不足一半）
    case warnInk
    /// 对照 / 占位灰
    case ghost
    /// 缓存堆叠段
    case cacheStack
    /// 卡片 0.5pt 描边
    case cardStroke
    /// 卡片顶部 1pt 高光
    case cardHighlight
}

/// 一个角色在某种外观下的取值
///
/// 支持两种表达，是为了让「默认主题零变化」：现有文字色是 `labelColor` 按 alpha 派生
/// （88% / 62%），换成写死的 hex 会在深色下改变观感与对比度，因此保留系统色通道。
public enum ThemeColor: Sendable, Equatable {
    /// 精确 sRGB 色（0xRRGGBB）
    case hex(UInt32)
    /// `labelColor` 按 alpha 叠加（随系统深浅自动反白，对比度由系统保证）
    case label(Double)
    /// 纯白按 alpha 叠加（高光边专用：深色下同样用白色，靠低 alpha 收敛）
    case white(Double)
    /// 系统强调色（`controlAccentColor`，跟随用户在系统设置里选的颜色）
    case systemAccent

    /// 用到的 hex 值（非 `.hex` 返回 nil，供对比度断言跳过）
    public var hexValue: UInt32? {
        if case let .hex(value) = self { return value }
        return nil
    }

    /// 转成 sRGB 分量（`.label` 返回 nil）
    public var rgb: SystemPaletteRGB? {
        guard let hexValue else { return nil }
        return SystemPaletteRGB(hex: hexValue)
    }
}

/// 角色 × 浅深两档
public struct ThemeColorPair: Sendable, Equatable {
    public let light: ThemeColor
    public let dark: ThemeColor

    public init(light: ThemeColor, dark: ThemeColor) {
        self.light = light
        self.dark = dark
    }

    /// 指定外观取值
    public func color(dark isDark: Bool) -> ThemeColor { isDark ? dark : light }
}

/// 玻璃配方 — 三层（面板 / 卡片 / 弹窗）共用的强度参数
public struct ThemeMaterialRecipe: Sendable, Equatable {

    /// 玻璃风格；`none` = 不启用任何材质（回到不透明实色）
    public enum Style: String, Sendable {
        case regular
        case clear
        case none
    }

    public let style: Style
    /// 卡片半透明底 alpha（1 = 不透明实色，0.72 = 通透）
    public let cardFillAlpha: Double
    /// 卡片顶部 1pt 高光 alpha
    public let highlightAlpha: Double
    /// 卡片 0.5pt 描边 alpha
    public let strokeAlpha: Double
    /// 面板叠加着色 alpha（0 = 完全沿用系统 windowBackgroundColor）
    public let panelTintAlpha: Double

    public init(style: Style, cardFillAlpha: Double, highlightAlpha: Double,
                strokeAlpha: Double, panelTintAlpha: Double) {
        self.style = style
        self.cardFillAlpha = cardFillAlpha
        self.highlightAlpha = highlightAlpha
        self.strokeAlpha = strokeAlpha
        self.panelTintAlpha = panelTintAlpha
    }

    /// 不启用玻璃时的配方：全不透明、无高光、无着色
    public static let opaque = Self(style: .none, cardFillAlpha: 1, highlightAlpha: 0,
                                    strokeAlpha: 0, panelTintAlpha: 0)
}

/// 阴影配方（弹窗层级用）
public struct ThemeShadowRecipe: Sendable, Equatable {
    public let radius: Double
    public let offsetY: Double
    public let opacity: Double

    public init(radius: Double, offsetY: Double, opacity: Double) {
        self.radius = radius
        self.offsetY = offsetY
        self.opacity = opacity
    }
}

/// 一套主题的完整定义
public struct Theme: Sendable, Equatable {

    public let id: ThemeID
    public let displayName: String
    public let detail: String
    /// 角色 → 浅深两档；缺角色由 `fallback` 兜底（新增角色不会让老主题崩）
    public let colors: [ThemeRole: ThemeColorPair]
    public let material: ThemeMaterialRecipe
    public let shadow: ThemeShadowRecipe

    public init(id: ThemeID, displayName: String, detail: String,
                colors: [ThemeRole: ThemeColorPair],
                material: ThemeMaterialRecipe, shadow: ThemeShadowRecipe) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.colors = colors
        self.material = material
        self.shadow = shadow
    }

    /// 取角色色；缺失时按角色语义回落（文字类走 label，其余走中性灰）
    public func color(_ role: ThemeRole, dark isDark: Bool) -> ThemeColor {
        if let pair = colors[role] { return pair.color(dark: isDark) }
        return Self.fallback(role)
    }

    /// 缺角色兜底 —— 保证任一主题都能画完整界面
    public static func fallback(_ role: ThemeRole) -> ThemeColor {
        switch role {
        case .textPrimary: return .label(1)
        case .textSecondary: return .label(0.88)
        case .textTertiary: return .label(0.62)
        case .accent: return .hex(0x0071E3)
        case .cardHighlight: return .label(0.10)
        case .cardStroke: return .label(0.10)
        case .selectedFill: return .label(0.07)
        case .track: return .label(0.14)
        case .trackStrong: return .label(0.24)
        case .hairline: return .label(0.10)
        case .grid: return .label(0.08)
        case .ok, .okInk: return .hex(0x14913F)
        case .warnInk: return .hex(0x8A5A06)
        case .ghost: return .hex(0xB4B4BE)
        case .panelTint: return .hex(0x000000)
        case .surface: return .hex(0xFFFFFF)
        default: return .label(0.10)
        }
    }
}
