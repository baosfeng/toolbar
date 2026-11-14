import Foundation

// MARK: - 主线程停顿判定（看门狗口径）

/// 主线程看门狗口径 — 判定与日志正文收敛在这里，App 层计时器与测试共用
///
/// 背景：面板「未响应」的现场没有一条本应用日志，事后只能靠 `sample` 反推
/// （2026-11 事故：CPU 99.4% 持续 2 s，生产日志为零）。把「多久算停顿」「日志写哪几个字段」
/// 变成纯函数后，判定阈值与脱敏都能被断言，不必再靠事后猜。
public enum MainThreadWatchdogPolicy {

    /// 后台看护节拍（秒）
    public static let tickSeconds: TimeInterval = 0.5
    /// 两次心跳间隔超过该值视为主线程停顿（秒）
    public static let stallThresholdSeconds: TimeInterval = 2

    /// 间隔是否达到「停顿」判据（严格大于阈值）
    public static func isStalled(gapSeconds: TimeInterval) -> Bool {
        gapSeconds > stallThresholdSeconds
    }

    /// 停顿日志正文：停顿时长 + 当前分页 + 面板是否展开 + Token 索引状态
    ///
    /// 索引状态里可能带会话目录路径（`failed(message:)`，路径夹在句中），一律先过
    /// `LogRedaction.paths(in:)`（全位置替换，不用只看前缀的 `path(_:)`）：
    /// OSLog 的 public 字段本机任何进程都能读。
    public static func message(gapSeconds: TimeInterval, tab: String, panelShown: Bool,
                               indexingState: String) -> String {
        String(format: "主线程停顿 %.1f s（阈值 %.0f s）— 分页=%@，面板展开=%@，Token索引=%@",
               gapSeconds, stallThresholdSeconds, tab, panelShown ? "是" : "否",
               LogRedaction.paths(in: indexingState))
    }
}
