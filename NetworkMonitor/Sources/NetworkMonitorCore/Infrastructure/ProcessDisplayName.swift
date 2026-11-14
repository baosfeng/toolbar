import Foundation

// MARK: - 本应用进程的显示名

/// 进程显示名映射 —— 把「本应用自己的进程」在界面上显示成 `AppIdentity.displayName`（「一览」）
///
/// **只改显示层**：采样侧给出的原始进程名（nettop / proc_name）保持不变，图标解析、榜单排序、
/// 内容签名与日志仍按原名走；因此这是一个纯展示变换，TestRunner 可以直接断言而不必起 UI。
///
/// 判据优先级（两条都是**精确匹配**，不做通配替换）：
/// 1. **pid 相同**：`pid == 本进程 pid` → 显示名（nettop / proc_name 都带 pid，这是主判据）
/// 2. **名字相同**：拿不到 pid（快照 / 夹具 / pid ≤ 0）时，退化为「进程名 == 本进程名」
///
/// `NetworkMonitor` 这串在别的上下文里可能指真·网络监控进程（nettop、第三方工具、调试副本），
/// 因此近似串（`NetworkMonitorX`、`Nettop`、大小写变体）一律原样返回——白名单只认
/// 「确实是本进程」这一条判据，不认任何名字前缀 / 后缀。
///
/// 截断不在本函数里做：长名省略号由界面标签的 `lineBreakMode` 负责，
/// 映射后的中文名走同一套标签规则，映射本身不改动长度。
public enum ProcessDisplayName {

    /// 进程在界面上显示的名字
    ///
    /// - Parameters:
    ///   - rawName: 采样给出的原始进程名（空串表示采样失败，原样返回，不伪造本应用名）
    ///   - pid: 该进程的 pid（≤ 0 表示不可得，退化为名字判据）
    ///   - currentPID: 本进程 pid（≤ 0 表示不可得）
    ///   - currentProcessName: 本进程名（`ProcessInfo.processInfo.processName`）
    public static func displayName(for rawName: String,
                                   pid: Int32,
                                   currentPID: Int32,
                                   currentProcessName: String) -> String {
        guard !rawName.isEmpty else { return rawName }
        let isSelf: Bool
        if pid > 0, currentPID > 0 {
            isSelf = pid == currentPID
        } else {
            isSelf = rawName == currentProcessName
        }
        // 映射结果等于原名（包内可执行名已是「一览」）时同样走这里，不做二次处理
        return isSelf ? AppIdentity.displayName : rawName
    }
}
