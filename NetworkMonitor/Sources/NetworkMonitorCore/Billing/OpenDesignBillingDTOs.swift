import Foundation

// MARK: - Open Design 响应 DTO 与时间范围映射

/// 本文件承载 Open Design provider 的数据契约部分：
/// 响应 DTO（字段名与 API 原样一致）、workspaceId 缓存、`BillingRange` 的查询窗口映射。
/// 拆出原因：provider 主体超过单文件 15 KiB 上限，按「主类 + 数据契约」范式分离。

// MARK: - workspaceId 缓存

/// workspaceId 缓存 — 按 token 记忆发现结果，凭据失效时整体清空
///
/// 用锁而非 actor：provider 需满足 `Sendable` 且调用点是并发上下文，简单同步锁足够。
/// 访问级别为 internal：本类型与 DTO 供同模块 provider 使用，故不复用 private
final class WorkspaceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: String] = [:]

    func value(for token: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[token]
    }

    func store(_ workspaceID: String, for token: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[token] = workspaceID
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}

// MARK: - 响应 DTO（字段名与 API 原样一致）

struct OpenDesignWorkspaceListDTO: Decodable {
    struct Item: Decodable {
        let workspaceId: String
    }

    let items: [Item]
}

struct OpenDesignCodingPlanDTO: Decodable {
    struct Window: Decodable {
        let policyId: String
        let durationSeconds: Double?
        let usedCredits: String
        let limitCredits: String
        let remainingCredits: String
        let resetsAt: String?
    }

    /// 是否具备编码计划资格（false 时服务端不下发窗口）
    let eligible: Bool
    let tier: String?
    let windows: [Window]
}

struct OpenDesignUsageDTO: Decodable {
    struct SummaryDTO: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens
        }
    }

    struct FilterOptionsDTO: Decodable {
        let runtimes: [String]?
    }

    /// 请求数（服务端给的是全范围总条数，不是当页条数）
    let totalCount: Int?
    let summary: SummaryDTO
    let filterOptions: FilterOptionsDTO?

    /// 映射为通用指标：请求数取 totalCount，token 取 summary；
    /// 金额留空（编码计划 chargeCredits 恒为 0、listChargedUsd 仅为标价）
    var metrics: BillingMetrics {
        BillingMetrics(requestCount: totalCount ?? 0,
                       usageUSD: nil,
                       inputTokens: summary.inputTokens,
                       cachedInputTokens: summary.cacheReadTokens,
                       outputTokens: summary.outputTokens)
    }
}

// MARK: - 时间范围映射

extension BillingRange {
    /// 服务端允许的最长查询跨度（秒）
    ///
    /// 实测 `/billing/usage` 只接受最近 7 天的窗口：跨度超过 7 天、或起点早于 7 天前，
    /// 一律返回 400 `invalid_workspace_usage_time_range`；终点晚于当前时刻同样报错。
    static let openDesignUsageMaxSpan: TimeInterval = 7 * 86_400

    /// 范围 → 聚合粒度（24h 按小时，其余按天）
    public var granularity: BillingGranularity {
        self == .last24Hours ? .hour : .day
    }

    /// 范围 → 查询窗口（截至当前时刻，向前推对应时长；
    /// 24 小时按小时起点对齐（23 个整点步长），7/30 天按自然日起点对齐）
    ///
    /// 终点夹到 `now`：自然日口径算出的终点是「明天 0 点」，属于未来时刻，
    /// 服务端直接 400 拒绝；起点不早于 7 天前，跨度超出部分裁掉，避免整段被拒。
    public func queryWindow(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let raw: DateInterval
        switch self {
        case .last24Hours:
            // 用当前小时起点做锚点：不依赖 date(bySetting:)（它会取严格之后的匹配，
            // 端点可能落到未来整点，正是服务端判非法范围的来源）
            let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start = calendar.date(byAdding: .hour, value: -23, to: hourStart) ?? hourStart
            raw = DateInterval(start: start, end: hourStart)
        case .last7Days:
            raw = dayWindow(days: 7, now: now, calendar: calendar)
        case .last30Days:
            raw = dayWindow(days: 30, now: now, calendar: calendar)
        }
        let end = min(raw.end, now)
        let earliest = now.addingTimeInterval(-Self.openDesignUsageMaxSpan)
        let start = max(raw.start, earliest)
        return DateInterval(start: start, end: max(start, end))
    }

    /// 以「当日 00:00」为起点、往前回溯 days 天的自然日窗口
    private func dayWindow(days: Int, now: Date, calendar: Calendar) -> DateInterval {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let end = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        return DateInterval(start: start, end: end)
    }
}
