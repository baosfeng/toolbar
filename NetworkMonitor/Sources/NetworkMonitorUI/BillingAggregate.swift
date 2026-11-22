import Foundation
import NetworkMonitorCore

// MARK: - 额度页总表口径（纯逻辑，可单测）

/// 总表口径 —— 窗口列怎么对齐、行怎么排、限流怎么数
///
/// 存在理由：v2 版式把「一个 provider 一张卡」改成「一屏一张表」，于是
/// 「列数取谁、不足的列怎么补、谁算限流、谁走余额行」全部成了页面口径。
/// 这些判据留在视图里就跑不了断言（TestRunner 进不了可执行 target），故抽到 UI 库。
public enum BillingAggregate {

    // MARK: - 总表：窗口列

    /// 一个 provider 的某一窗口列（表格里的一格）
    public struct WindowColumn: Equatable {
        /// 窗口名（「会话」/「每周」/「5 小时」）
        public let title: String
        /// 剩余比例 0…1（nil = 不可得，画「—」且不画填充）
        public let remaining: Double?
        /// 下次重置时刻（nil = 无重置窗口）
        public let resetsAt: Date?
        /// provider 给的角标（如「已限流」）
        public let badge: String?

        public init(title: String, remaining: Double?, resetsAt: Date?, badge: String? = nil) {
            self.title = title
            self.remaining = remaining
            self.resetsAt = resetsAt
            self.badge = badge
        }
    }

    /// 总表里的一行（一个 provider）
    public struct ProviderRow: Equatable {
        /// 实例标识
        public let id: String
        /// 主名（不含实例后缀，如 «Open Design»）
        public let name: String
        /// 实例副标（命名实例的标签，如 «home»；nil = 默认实例）
        public let subtitle: String?
        /// 该 provider 的窗口列（0 列 = 纯余额型）
        public let windows: [WindowColumn]
        /// 是否纯余额型（表下段金额行）
        public let isBalanceOnly: Bool

        public init(id: String, name: String, subtitle: String? = nil,
                    windows: [WindowColumn], isBalanceOnly: Bool) {
            self.id = id
            self.name = name
            self.subtitle = subtitle
            self.windows = windows
            self.isBalanceOnly = isBalanceOnly
        }

        /// 完整展示名（主名 + 副标）：读屏与二级页标题用它
        public var fullName: String {
            guard let subtitle, !subtitle.isEmpty else { return name }
            return name + " (" + subtitle + ")"
        }
    }

    /// 总表最多几列（面板 320pt 下每列约 86pt，四列会把数值挤断）
    public static let maxColumns = 3

    /// 告警阈值（与 BillingProviderStatusLogic.warnThreshold 同值，额度页内唯一口径）
    public static let warnThreshold: Double = 0.2

    /// 跨 provider 的窗口列数 —— 取各家窗口数的最大值（封顶 maxColumns）
    ///
    /// 表格每行窗口数不同（Ollama 2 个、OpenCode Go 3 个），列宽必须全表统一，
    /// 所以行内不足的列要留空位占住宽度，否则最后一行两列会撑宽整表。
    public static func columnCount(_ rows: [ProviderRow]) -> Int {
        min(rows.map(\.windows.count).max() ?? 0, maxColumns)
    }

    /// 把一行补齐到指定列数（nil = 空位，只占宽度不画内容）
    public static func padded(_ row: ProviderRow, columnCount: Int) -> [WindowColumn?] {
        guard columnCount > 0 else { return [] }
        return (0..<columnCount).map { index in
            index < row.windows.count ? row.windows[index] : nil
        }
    }

    /// 被限流的 provider 数（页脚状态带的「限流」项）
    ///
    /// 判据与状态胶囊同源：任一窗口带角标，或剩余比例低于告警阈值。
    public static func throttledCount(_ rows: [ProviderRow]) -> Int {
        rows.filter { row in
            row.windows.contains { column in
                (column.badge?.isEmpty == false) || (column.remaining ?? 1) < warnThreshold
            }
        }.count
    }

    // MARK: - 总表：行构造

    /// 从 provider 运行时状态构造总表行 —— 视图不再自己判「谁进表、谁走金额行」
    ///
    /// 排序沿用输入顺序（= provider 注册顺序）：用户按启用顺序认牌子，
    /// 按剩余比例重排会让每次刷新后行位跳动。
    ///
    /// - Parameters:
    ///   - ids: 实例标识
    ///   - names: 展示名
    ///   - columns: 每家的窗口列（顺序即表格列序）
    public static func rows(entries: [(id: String, name: String, subtitle: String?,
                                       windows: [WindowColumn])]) -> [ProviderRow] {
        entries.map { entry in
            ProviderRow(id: entry.id,
                        name: entry.name,
                        subtitle: entry.subtitle,
                        windows: Array(entry.windows.prefix(maxColumns)),
                        isBalanceOnly: entry.windows.isEmpty)
        }
    }
}
