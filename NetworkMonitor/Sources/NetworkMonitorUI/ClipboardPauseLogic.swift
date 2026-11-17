import Foundation

// MARK: - 采集暂停（纯口径）

/// 剪贴板采集暂停的纯口径 —— 默认值、可见文案与菜单标题
///
/// 与 `ClipboardCaptureMode`（怎么采）是两个维度：这里决定「采不采」。
/// 全部为纯函数，不依赖 AppKit / 偏好存储，供面板、菜单栏、设置页与 TestRunner 共用一份口径。
public enum ClipboardPauseLogic {

    /// 切换暂停的组合键（面板键位帮助浮层与提示行共用同一份文字）
    public static let toggleKeyHint = "⌘P"

    /// 暂停开关的默认值：未写入过即未暂停（老用户升级后行为不变）
    public static func isPaused(storedValue: Bool?) -> Bool {
        storedValue ?? false
    }

    /// 是否需要真的执行一次暂停 / 恢复（幂等判据）
    ///
    /// 暂停与恢复共用这一条：目标态与当前态相同即无事可做，调用方不得重复停轮询、
    /// 重复注册观察者或重复打日志。实现与测试共用同一份口径，避免两处各写一遍。
    public static func shouldTransition(currentlyPaused: Bool, target: Bool) -> Bool {
        currentlyPaused != target
    }

    /// 提示行空闲文案：暂停时常驻「已暂停」，否则回到键位帮助
    ///
    /// - Parameters:
    ///   - isPaused: 当前是否暂停
    ///   - idleHint: 未暂停时的键位帮助文案
    public static func footerHint(isPaused: Bool, idleHint: String) -> String {
        isPaused ? "采集已暂停（点此或 \(toggleKeyHint) 恢复）" : idleHint
    }

    /// 右键菜单项标题：按当前状态给出「接下来能做的事」
    public static func menuTitle(isPaused: Bool) -> String {
        isPaused ? "恢复采集" : "暂停采集"
    }

    /// 状态栏标题前缀：暂停时给一个可辨识的标记，正常时为空串
    public static func statusPrefix(isPaused: Bool) -> String {
        isPaused ? "⏸ " : ""
    }

    /// 暂停态点「采集当前剪贴板」被拒的提示（不得静默）
    public static var captureBlockedHint: String {
        "采集已暂停（\(toggleKeyHint) 或菜单「恢复采集」可恢复）"
    }
}
