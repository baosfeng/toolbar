import Foundation
import NetworkMonitorCore

// MARK: - 本应用进程名的显示口径

/// 把「本应用自己的进程」显示成 `AppIdentity.displayName`（「一览」）
///
/// 采样侧（nettop / proc_name）给的是系统进程名；包内可执行名已是「一览」时两者相同，
/// 映射自然落空、原样返回。保留映射作为兜底：旧包（可执行名仍是 NetworkMonitor）、
/// 调试副本、以及采样名被截断的场景同样能显示中文名。
///
/// 本进程 pid / 进程名只读一次（进程生命周期内不变），避免每行每帧都调 ProcessInfo。
enum AppProcessName {

    /// 本进程 pid
    private static let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)

    /// 本进程名（= 包内可执行名）
    private static let currentProcessName = ProcessInfo.processInfo.processName

    /// 显示名（判据见 `ProcessDisplayName`）
    static func displayName(_ rawName: String, pid: Int32) -> String {
        ProcessDisplayName.displayName(for: rawName,
                                       pid: pid,
                                       currentPID: currentPID,
                                       currentProcessName: currentProcessName)
    }
}
