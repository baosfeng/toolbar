import AppKit

// MARK: - Token 页样式令牌

/// Token 页字体 / 颜色 / 尺寸 —— 对齐定稿原型 c 版
///
/// 通用语义色仍走 `MenuPanelStyle`；这里补图表三色、卡片底色与斜纹图案。
@MainActor
enum TokenPaneStyle {

    // MARK: 字体

    /// 页头标题
    static let pageTitleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    /// hero 主数字（24pt 等宽半粗）
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
    /// hero 单位说明
    static let heroUnitFont = NSFont.systemFont(ofSize: 11)
    /// 分区标题（11pt 半粗）
    static let sectionTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// 分区补充说明（9pt）
    static let metaFont = NSFont.systemFont(ofSize: 9)
    /// 坐标轴 / 时间（9pt 等宽）
    static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 图例（9pt）
    static let legendFont = NSFont.systemFont(ofSize: 9)
    /// 三项分卡：标题（10pt）
    static let chipTitleFont = NSFont.systemFont(ofSize: 10)
    /// 三项分卡：数值（13pt 等宽半粗）
    static let chipValueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    /// 三项分卡：占比（9pt）
    static let chipShareFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 环比徽标：标题（9pt）
    static let badgeTitleFont = NSFont.systemFont(ofSize: 9)
    /// 环比徽标：数值（10pt 等宽半粗）
    static let badgeValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 迷你图标题（10pt）
    static let miniTitleFont = NSFont.systemFont(ofSize: 10)
    /// 迷你图数值（11pt 等宽半粗）
    static let miniValueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// 列表主名（11pt）
    static let listNameFont = NSFont.systemFont(ofSize: 11)
    /// 列表副标签（9pt）
    static let listSubFont = NSFont.systemFont(ofSize: 9)
    /// 列表数值（10pt 等宽半粗）
    static let listValueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 页脚说明（9pt）
    static let footerFont = NSFont.systemFont(ofSize: 9)
    /// 分段按钮（9pt）
    static let segmentFont = NSFont.systemFont(ofSize: 9)
    /// 分段按钮选中态（9pt 半粗）
    static let segmentSelectedFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    /// 状态页正文（12pt）
    static let stateBodyFont = NSFont.systemFont(ofSize: 12)
    /// 状态页说明（10pt）
    static let stateNoteFont = NSFont.systemFont(ofSize: 10)

    // MARK: 颜色

    /// 缓存读 —— 强调色
    static var cacheColor: NSColor { .controlAccentColor }
    /// 输出 —— 强调色 45% + 前景色 55%
    static var outputColor: NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
            return blend(accent, with: labelBase(appearance), accentRatio: 0.45)
        }
    }
    /// 未缓存输入 —— 前景色 42%
    static var inputColor: NSColor { translucent(0.42) }
    /// 昨日同期柱（幽灵柱）
    static var ghostColor: NSColor { translucent(0.22) }
    /// 轨道 / 空档斜纹 / 分隔
    static var trackColor: NSColor { translucent(0.14) }
    /// 卡片底
    static var cardFill: NSColor { translucent(0.055) }
    /// 卡片描边 / 细线
    static var hairline: NSColor { translucent(0.10) }
    /// 当前小时淡底
    static var currentHourWash: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.10) }
    /// 分段选中底
    static var selectedFill: NSColor { translucent(0.12) }
    /// 文本：次要 / 三级（沿用面板语义色）
    static var secondaryText: NSColor { MenuPanelStyle.secondaryText }
    static var tertiaryText: NSColor { MenuPanelStyle.tertiaryText }

    // MARK: 尺寸

    /// 卡片圆角
    static let cardInset: CGFloat = 10
    /// 小时图高度
    static let hourChartHeight: CGFloat = 92
    /// 按天趋势高度
    static let trendChartHeight: CGFloat = 100
    /// 迷你图高度
    static let miniChartHeight: CGFloat = 30
    /// 迷你图行高（标题 + 图）
    static let miniHeight: CGFloat = 46
    /// 环形图直径
    static let donutSize: CGFloat = 86
    /// 环形图环宽
    static let donutRingWidth: CGFloat = 10

    // MARK: - 工具

    /// 前景色按透明度混合（动态解析，外观切换后重新取基准色）
    static func translucent(_ alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            labelBase(appearance).withAlphaComponent(alpha)
        }
    }

    /// 当前外观下的前景基色（深色白 / 浅色黑）
    private static func labelBase(_ appearance: NSAppearance) -> NSColor {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }

    /// 两色线性混合（sRGB 空间）
    static func blend(_ base: NSColor, with other: NSColor, accentRatio: CGFloat) -> NSColor {
        let a = base.usingColorSpace(.sRGB) ?? base
        let b = other.usingColorSpace(.sRGB) ?? other
        return NSColor(srgbRed: a.redComponent * accentRatio + b.redComponent * (1 - accentRatio),
                       green: a.greenComponent * accentRatio + b.greenComponent * (1 - accentRatio),
                       blue: a.blueComponent * accentRatio + b.blueComponent * (1 - accentRatio),
                       alpha: 1)
    }

    /// 模型环形图配色：Top5 由强调色向文字色渐变
    static func modelColor(_ index: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
            let base = labelBase(appearance)
            switch index {
            case 0: return accent
            case 1: return blend(accent, with: base, accentRatio: 0.74)
            case 2: return blend(accent, with: base, accentRatio: 0.56)
            case 3: return blend(accent, with: base, accentRatio: 0.40)
            case 4: return blend(accent, with: base, accentRatio: 0.26)
            default: return base.withAlphaComponent(0.22)
            }
        }
    }
}
