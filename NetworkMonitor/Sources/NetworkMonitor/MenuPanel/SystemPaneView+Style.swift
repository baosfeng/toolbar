import AppKit

// MARK: - 系统页派生样式（v2 增量指标）

/// 系统页增量指标的派生样式 — 颜色全部由强调色与灰阶混出，不引入紫 / 青
///
/// 深色主题下强调色与前景基色同时变化，故一律用动态 provider：每次绘制按当前外观
/// 重新解析，强制外观渲染（快照取证）时不会残留浅色下的旧值（同 `MenuPanelStyle.dynamicLabel`）。
/// 混合在 sRGB 空间按比例插值（与 `TokenPaneStyle.blend` 同一做法）。
@MainActor
enum SystemPaneStyle {

    /// 9pt 微标签字体（内存四段说明字、图例文字）
    static let microFont = NSFont.systemFont(ofSize: 9, weight: .regular)

    /// CPU 系统态带 — 强调色 54% + 前景 46%（与用户态面积同族、更深一档）
    static var systemUsageBand: NSColor { mixed(accentRatio: 0.54) }

    /// 内存 wired 段 — 强调色 60% + 前景 40%（最深的蓝，对应不可换出）
    static var memoryWired: NSColor { mixed(accentRatio: 0.60) }

    /// 内存 active 段 — 强调色原色（主蓝）
    static var memoryActive: NSColor { NSColor.controlAccentColor }

    /// 内存 compressed 段 — 强调色 66% 不透明（在灰轨道上仍可辨）
    ///
    /// 用动态 provider 而非 `controlAccentColor.withAlphaComponent`：后者在调用瞬间解析并固化
    /// CGColor，强制外观渲染时深色会拿到浅色下的蓝。
    static var memoryCompressed: NSColor {
        NSColor(name: nil) { _ in
            NSColor.controlAccentColor.withAlphaComponent(0.66)
        }
    }

    /// IOPS 虚线（读）— 54% 前景灰（非文本图形色，浅色下仍有 3:1 以上）
    static var iopsPrimary: NSColor { MenuPanelStyle.dynamicLabel(alpha: 0.54) }

    /// IOPS 虚线（写）— 30% 前景灰，同图内靠明度与读序列区分
    static var iopsSecondary: NSColor { MenuPanelStyle.dynamicLabel(alpha: 0.30) }

    // MARK: 混合

    /// 强调色与前景基色按 `accentRatio` 在 sRGB 空间插值
    private static func mixed(accentRatio: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let ink = (isDark ? NSColor.white : NSColor.black).usingColorSpace(.sRGB) ?? NSColor.black
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
            return NSColor(srgbRed: accent.redComponent * accentRatio + ink.redComponent * (1 - accentRatio),
                           green: accent.greenComponent * accentRatio + ink.greenComponent * (1 - accentRatio),
                           blue: accent.blueComponent * accentRatio + ink.blueComponent * (1 - accentRatio),
                           alpha: 1)
        }
    }
}
