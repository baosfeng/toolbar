import Foundation

// MARK: - 菜单项 tag 可清理区间

/// 判断某个菜单项 tag 是否属于「可被动态清理」的区间（纯 Int 逻辑，与 AppKit 无关）。
///
/// 放在 NetworkMonitorCore 而不是 App 层，是为了让 TestRunner 能直接覆盖这段判断：
/// TestRunner 只依赖 NetworkMonitorCore，拿不到 App 层的 NSMenu / NSMenuItem 类型。
/// MenuBarManager 与测试共用这里同一份规则，避免两处各写一份判断而再次走偏。
public enum MenuTagRange {
    /// 每小时迷你图表等动态条目的起始 tag（动态条目从这里开始连续编号）。
    public static let hourlyBaseTag = 4200
    /// 动态条目占用的 tag 数量，实际区间为 [hourlyBaseTag, hourlyBaseTag + hourlySpan)。
    public static let hourlySpan = 100

    /// 该 tag 是否为「每小时动态条目」，即是否可以直接从菜单中移除。
    ///
    /// 必须是**有界区间**，不能写成 `tag >= hourlyBaseTag`：
    /// 历史事故 —— 原实现按「tag >= 4200」从后往前扫描整个一级菜单并 removeItem，
    /// 于是 tag 7001（剪贴板历史）、7002（剪贴板设置）这类高位一级菜单项被一并误删；
    /// 触发点在菜单显示之前的 menuWillOpen 阶段，因此用户永远看不到这两个入口
    /// （只剩两条入口之间那条 tag=0 的孤立分隔线）。判定收窄到区间后即不会再误伤。
    public static func isDynamicHourlyTag(_ tag: Int) -> Bool {
        tag >= hourlyBaseTag && tag < hourlyBaseTag + hourlySpan
    }
}
