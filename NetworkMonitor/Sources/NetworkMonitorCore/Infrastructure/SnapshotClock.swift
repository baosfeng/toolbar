import Foundation

// MARK: - 快照时钟注入点

/// 快照时钟 — 快照通道读时间的**唯一**注入点
///
/// 背景：同一份快照函数既出验收图、又做逐像素回归比对；Token / 额度页里有实时数值与时钟，
/// 同一份代码连跑两次差异约 10%，逐像素比对永远收敛不了。
///
/// 用法：`NM_SNAPSHOT_FREEZE=<epoch 秒>`（DEBUG 构建生效），所有快照路径读时间一律走
/// `SnapshotClock.now`；不设环境变量时它**就是** `Date()`，语义与性能都与改造前一致。
///
/// 值形式：
/// - 缺省 / 空串 → 未冻结（回落真实时钟）
/// - `now` → 取当前时刻并对齐到整分钟（同一次运行内多次取到的值相同）
/// - 十进制 epoch 秒 → 固定时刻
public enum SnapshotClock {

    /// 环境变量名
    public static let environmentKey = "NM_SNAPSHOT_FREEZE"

    /// 冻结时刻（nil = 未冻结）
    ///
    /// 只解析一次：环境变量在进程生命周期内不变，避免每次取时间都查一遍。
    /// release 构建恒为 nil —— 冻结是取证能力，不进生产语义。
    public static let frozen: Date? = {
#if DEBUG
        parse(ProcessInfo.processInfo.environment[environmentKey])
#else
        nil
#endif
    }()

    /// 是否处于冻结模式
    public static var isFrozen: Bool { frozen != nil }

    /// 当前时刻：冻结时返回固定值，未冻结时等价于 `Date()`
    public static var now: Date { frozen ?? Date() }

    /// 解析环境变量取值（- Parameter reference: `now` 形式对齐整分钟的参照时刻，测试可注入）
    public static func parse(_ raw: String?, reference: Date = Date()) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "now" {
            // 对齐整分钟：否则同一进程内两次读取仍会差几毫秒
            return Date(timeIntervalSince1970: (reference.timeIntervalSince1970 / 60).rounded(.down) * 60)
        }
        guard let seconds = Double(raw), seconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
