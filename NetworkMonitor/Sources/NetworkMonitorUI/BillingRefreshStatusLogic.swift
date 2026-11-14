import Foundation

// MARK: - 额度页刷新状态文案（纯逻辑，可单测）

/// 刷新状态文案 —— 把「是否因锁屏 / 休眠暂停」翻译成面板要显示的两处文案
///
/// 抽成纯逻辑的原因：`BillingMonitor` 在可执行 target 里，TestRunner 依赖不到；
/// 而这两句文案正是「额度没用了」现场唯一能自证的东西（时间戳停住 + 页脚说「已暂停」）。
/// 判据放这里即可直接断言，视图只做透传。
public enum BillingRefreshStatusLogic {

    /// Hero 右上角的时钟文案
    ///
    /// - Parameters:
    ///   - isPaused: 后台刷新是否处于暂停态（锁屏 / 休眠）
    ///   - latestStamp: 最近一次成功刷新的时分（从未刷新时为「—」）
    public static func clockText(isPaused: Bool, latestStamp: String) -> String {
        guard !isPaused else { return "已暂停 · 恢复亮屏后自动刷新" }
        // 还没成功刷新过时不拼「实时 —」：那是把「不可得」写成了半句话
        return latestStamp == "—" ? "尚未刷新" : "实时 " + latestStamp
    }

    /// 页脚状态带「刷新」项的值
    ///
    /// 只写「已暂停」：346pt 的面板里这一带只放得下四项，
    /// 更长的「已暂停（锁屏 / 休眠）」会把相邻的「单位」挤成「中…」；
    /// 具体原因与出路由 Hero 右侧那句给出。
    public static func bandText(isPaused: Bool) -> String {
        isPaused ? "已暂停" : "正常"
    }

    /// 是否该给「刷新」项上告警色（暂停时提醒用户这不是故障而是等待）
    public static func bandWarns(isPaused: Bool) -> Bool { isPaused }
}
