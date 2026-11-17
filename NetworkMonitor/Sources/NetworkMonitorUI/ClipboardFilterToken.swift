import Foundation
import NetworkMonitorCore

// MARK: - 类型过滤

/// 面板类型过滤（⇧Tab 循环与类型芯片共用一份口径）
///
/// 从面板视图搬到 NetworkMonitorUI：类型匹配是纯逻辑，TestRunner 要能直接断言，
/// 视图层只负责把它渲染成一枚可移除的芯片。
public enum ClipboardFilter: Int, CaseIterable, Sendable {
    case all
    case text
    case image
    case pinned

    /// 中文名称（芯片文案、循环过滤提示与无障碍描述共用）
    public var label: String {
        switch self {
        case .all: "全部"
        case .text: "文本"
        case .image: "图片"
        case .pinned: "收藏"
        }
    }

    /// 是否落成一枚可移除的类型芯片（.all 表示「不限制类型」，不占芯片位）
    public var isChip: Bool { self != .all }

    /// 条目是否命中该类型
    public func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: true
        case .text: item.kind == .text || item.kind == .rtf
        case .image: item.kind == .image
        case .pinned: item.isPinned
        }
    }
}

// MARK: - 日期档

/// 日期范围四档 —— 互斥分档：今天 / 近 7 天 / 近 30 天 / 更早
///
/// 分档按自然日算（走 Calendar.startOfDay），不受夏令时影响；四档互斥，
/// 因此同时选中两档只会得到空结果，不需要额外去重。
public enum ClipboardDateRange: String, CaseIterable, Sendable {
    case today
    case last7Days
    case last30Days
    case earlier

    /// 芯片文案
    public var label: String {
        switch self {
        case .today: "今天"
        case .last7Days: "近 7 天"
        case .last30Days: "近 30 天"
        case .earlier: "更早"
        }
    }

    /// 时间点是否落在本档内（未来时间按时钟漂移归入「今天」，不产生空档）
    public func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let monthStart = calendar.date(byAdding: .day, value: -29, to: today) ?? weekStart
        switch self {
        case .today: return date >= today
        case .last7Days: return date >= weekStart && date < today
        case .last30Days: return date >= monthStart && date < weekStart
        case .earlier: return date < monthStart
        }
    }
}

// MARK: - 芯片模型

/// 芯片类别（决定取值口径与可选清单分组）
public enum ClipboardFilterTokenKind: String, CaseIterable, Sendable {
    case type
    case source
    case date

    /// 可选清单里的分组标题
    public var menuTitle: String {
        switch self {
        case .type: "类型"
        case .source: "来源 App"
        case .date: "日期"
        }
    }
}

/// 一枚筛选芯片 —— 值类型，kind + value 即唯一键
///
/// value 的存法：类型存 ClipboardFilter.rawValue，来源存 App 名，日期存 ClipboardDateRange.rawValue。
/// 存原始值而不是索引，是为了让芯片在打包 / 解包与测试夹具之间是自描述的。
public struct ClipboardFilterToken: Equatable, Hashable, Sendable, Identifiable {
    public let kind: ClipboardFilterTokenKind
    public let value: String

    public init(kind: ClipboardFilterTokenKind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// 类型芯片
    public static func type(_ filter: ClipboardFilter) -> ClipboardFilterToken {
        ClipboardFilterToken(kind: .type, value: String(filter.rawValue))
    }

    /// 来源 App 芯片
    public static func source(_ appName: String) -> ClipboardFilterToken {
        ClipboardFilterToken(kind: .source, value: appName)
    }

    /// 日期芯片
    public static func date(_ range: ClipboardDateRange) -> ClipboardFilterToken {
        ClipboardFilterToken(kind: .date, value: range.rawValue)
    }

    public var id: String { kind.rawValue + ":" + value }

    /// 类型取值（非类型芯片为 nil）
    public var typeFilter: ClipboardFilter? {
        guard kind == .type else { return nil }
        return ClipboardFilter(rawValue: Int(value) ?? -1)
    }

    /// 日期取值（非日期芯片为 nil）
    public var dateRange: ClipboardDateRange? {
        guard kind == .date else { return nil }
        return ClipboardDateRange(rawValue: value)
    }

    /// 来源 App 名（非来源芯片为 nil）
    public var sourceName: String? { kind == .source ? value : nil }

    /// 芯片显示文案（取不到取值时回退原始串，不静默丢芯片）
    public var label: String {
        switch kind {
        case .type: typeFilter?.label ?? value
        case .source: value
        case .date: dateRange?.label ?? value
        }
    }

    /// 读屏说明：芯片是一个可移除的筛选条件
    public var accessibilityHint: String { "移除" + kind.menuTitle + "筛选" }
}

// MARK: - 叠加匹配

/// 多枚芯片的叠加匹配 —— 纯函数，与视图无关
///
/// 叠加规则：同一类别内是「或」（来源 Safari 或 Terminal），不同类别之间是「且」
/// （Safari 且 今天）。空芯片 = 不过滤。
public enum ClipboardFilterMatcher {

    /// 条目是否同时满足全部芯片
    public static func matches(_ item: ClipboardItem, tokens: [ClipboardFilterToken],
                               now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !tokens.isEmpty else { return true }
        for kind in ClipboardFilterTokenKind.allCases {
            let group = tokens.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            guard group.contains(where: { matches(item, token: $0, now: now, calendar: calendar) }) else {
                return false
            }
        }
        return true
    }

    /// 单枚芯片的判定（取值缺失时按「不限制」处理，不把整批结果清空）
    static func matches(_ item: ClipboardItem, token: ClipboardFilterToken,
                        now: Date, calendar: Calendar) -> Bool {
        switch token.kind {
        case .type:
            return token.typeFilter?.matches(item) ?? true
        case .source:
            guard let name = token.sourceName else { return true }
            return item.sourceAppName == name
        case .date:
            guard let range = token.dateRange else { return true }
            return range.contains(item.createdAt, now: now, calendar: calendar)
        }
    }
}

// MARK: - 来源 App 清单

/// 来源 App 候选清单 —— 从当前条目里聚合（去重 + 按出现次数排序 + 取前 N）
///
/// 不做全库历史 App 名录：清单跟着当前这批条目走，用户看到的就是「现在能筛出东西的来源」。
public enum ClipboardSourceCatalog {

    /// 一个来源候选：App 名 + 出现次数
    public struct Source: Equatable, Hashable, Sendable {
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    /// 聚合前 N 个来源（次数降序，同次数按名称本地化升序，保证顺序稳定）
    public static func topSources(items: [ClipboardItem], limit: Int = 8) -> [Source] {
        guard limit > 0 else { return [] }
        var counts: [String: Int] = [:]
        for item in items {
            guard let name = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }
            counts[name, default: 0] += 1
        }
        let sorted = counts.map { Source(name: $0.key, count: $0.value) }
            .sorted { left, right in
                left.count != right.count
                    ? left.count > right.count
                    : left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        return Array(sorted.prefix(limit))
    }
}

// MARK: - 类型芯片循环

/// Tab / ⇧Tab 的类型循环 —— 只轮换类型那一枚，来源与日期芯片原样保留
///
/// 轮换口径：无类型芯片 → 文本 → 图片 → 收藏 → 无类型芯片（回到「不限类型」）。
/// 循环到「不限类型」时摘掉类型芯片，而不是留一枚写着「全部」的芯片。
public enum ClipboardFilterCycle {

    /// 下一组芯片（其他类别的芯片保持在原位）
    ///
    /// 循环在「全部 → 文本 → 图片 → 收藏」上转，落到「全部」就是把类型芯片摘掉。
    public static func next(after tokens: [ClipboardFilterToken], reverse: Bool) -> [ClipboardFilterToken] {
        let order = ClipboardFilter.allCases
        let current = tokens.compactMap(\.typeFilter).first ?? .all
        let step = reverse ? order.count - 1 : 1
        let index = (order.firstIndex(of: current).map { $0 + step } ?? 0) % order.count
        let others = tokens.filter { $0.kind != .type }
        let picked = order[index]
        return picked.isChip ? others + [ClipboardFilterToken.type(picked)] : others
    }
}

