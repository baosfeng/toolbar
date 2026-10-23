import AppKit

// MARK: - 额度页样式令牌

/// 额度页专用字号与色块 — 与原型 CSS 对齐；通用颜色仍走 `MenuPanelStyle`
///
/// 从 `BillingPaneView.swift` 拆出（原文件超 15 KiB 规范上限），成员写法不变，
/// 调用方仍按 `BillingPaneStyle.xxx` 使用。
@MainActor
enum BillingPaneStyle {
    /// hero 金额（25pt 等宽半粗）
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 25, weight: .semibold)
    /// provider 名称（12pt 半粗）
    static let providerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// 卡片小标题 / 分区标题（11pt 半粗）
    static let cardTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// 正文（11pt）
    static let labelFont = NSFont.systemFont(ofSize: 11)
    /// 金额 / 数值（11pt 等宽）
    static let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// 指标数值（12pt 等宽半粗）
    static let metricValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    /// 说明与时间戳（10pt）
    static let subFont = NSFont.systemFont(ofSize: 10)
    /// 页头时间戳（10pt 等宽）
    static let stampFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 范围按钮（10pt 等宽）
    static let rangeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 范围按钮选中态（10pt 等宽半粗）
    static let rangeSelectedFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 图表坐标轴（9pt 等宽）
    static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 模型名（11pt 等宽）
    static let modelNameFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    /// 模型金额（11pt 等宽半粗）
    static let modelAmountFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// 模型请求数（10pt 等宽）
    static let modelRequestFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 说明段落（10.5pt）
    static let noteFont = NSFont.systemFont(ofSize: 10.5)

    /// 强调色浅底（范围选中态 15%）
    static var accentSoft: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.15) }
    /// 强调色图标容器底（12%）
    static var accentTile: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.12) }
    /// 危险色浅底（错误条 10%）
    static var dangerSoft: NSColor { NSColor.systemRed.withAlphaComponent(0.10) }
    /// 1pt 浅分隔线（10% 前景色，深浅色自适应）
    static var hairline: NSColor { NSColor.labelColor.withAlphaComponent(0.10) }
    /// 输入框边框（分隔线色，深浅色自适应）
    static var fieldBorder: NSColor { NSColor.separatorColor }

    // MARK: - 动态文字色

    /// 次要文字色 — 视觉对齐 `MenuPanelStyle.secondaryText`，但用 dynamicProvider 在绘制时解析
    ///
    /// 后者由 `labelColor.withAlphaComponent(...)` 生成、颜色创建时固化，切换外观后会残留旧色（浅色下变白）。
    static let secondaryText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor.black.withAlphaComponent(0.78)
    }

    /// 三级文字色 — 同为动态解析（视觉值对应 `MenuPanelStyle.tertiaryText`）
    static let tertiaryText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.62)
            : NSColor.black.withAlphaComponent(0.55)
    }
}
