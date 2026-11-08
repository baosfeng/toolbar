import AppKit
import NetworkMonitorCore

// MARK: - 截图设置委托

/// 设置窗内重新录制截图快捷键：冲突时由设置窗标红并保留原组合键
@MainActor
protocol SnipSettingsDelegate: AnyObject {
    func settingsDidChangeSnipHotKey(_ action: SnipHotKeyAction, combo: HotKeyCombo) -> Bool
}
