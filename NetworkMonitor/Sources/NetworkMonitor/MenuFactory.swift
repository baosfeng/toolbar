import AppKit

// MARK: - 菜单工厂

/// 菜单项工厂 — 纯函数式 NSMenuItem 创建工具
///
/// 从 MenuBarManager 提取，职责单一：仅负责生成菜单项。
public enum MenuFactory {

    /// 创建标准菜单项
    /// - Parameters:
    ///   - title: 标题
    ///   - action: 点击动作（nil 表示不可交互）
    ///   - keyEquivalent: 快捷键
    ///   - symbol: SF Symbol 名称
    ///   - tag: 标签
    ///   - isEnabled: 是否启用
    /// - Returns: 配置好的 NSMenuItem
    public static func item(
        title: String,
        action: Selector? = nil,
        keyEquivalent: String = "",
        symbol: String? = nil,
        tag: Int = 0,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.tag = tag
        item.isEnabled = isEnabled
        if let symbol {
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                let configured = img.withSymbolConfiguration(config) ?? img
                item.image = configured
                item.image?.isTemplate = true
            }
        }
        return item
    }

    /// 创建分隔线
    public static func separator() -> NSMenuItem {
        NSMenuItem.separator()
    }

    /// 短格式时间 "1h23m" / "45m"
    public static func formatDurationCompact(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }

    /// 紧凑数字格式（≥1万显示 K 单位）
    public static func formatCompactNumber(_ number: Int) -> String {
        if number >= 10000 {
            return String(format: "%.1fK", Double(number) / 1000)
        }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
