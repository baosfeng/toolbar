import AppKit

// MARK: - provider 行（控件工厂）

/// 控件工厂 —— 从 `+Editing` 拆出（同族合计门禁只降不升）
///
/// 行内文字按钮与主按钮的样式口径只在这里出现一次；按钮高度统一到 22pt，
/// 与右侧开关同一条横线。
extension ProviderRowView {

    // MARK: - 控件工厂

    static func textButton(_ title: String,
                           color: NSColor = SettingsTheme.accent) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.controlSize = .small
        button.font = SettingsTheme.rowTitleFont
        button.contentTintColor = color
        // 文字按钮与右侧开关同在一行：给同一档 22pt 高，横线才对得齐（不改字号与行为）
        SettingsControlChrome.applyStandardHeight(to: button)
        return button
    }

    static func primaryButton(_ title: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.bezelColor = SettingsTheme.accent
        button.contentTintColor = .white
        SettingsControlChrome.applyStandardHeight(to: button)
        return button
    }
}
