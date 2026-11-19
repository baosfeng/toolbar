import Foundation

// MARK: - Open Design 解码与格式化（provider 扩展）

/// provider 的纯函数部分：响应解码（public 供测试直接验证映射）与时间/窗口文案。
/// 拆出原因：provider 主体超过单文件 15 KiB 上限，按「主类 + 协议/纯函数扩展」范式分离。
extension OpenDesignBillingProvider {

    // MARK: - 解码（public 供测试直接验证映射）

    /// 解析工作区列表，取首个 workspaceId
    public static func decodeWorkspaceID(from data: Data) throws -> String {
        let dto: OpenDesignWorkspaceListDTO
        do {
            dto = try JSONDecoder().decode(OpenDesignWorkspaceListDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        guard let id = dto.items.first?.workspaceId, !id.isEmpty else {
            throw BillingError.invalidResponse("账号下没有可用工作区")
        }
        return id
    }

    /// 解析编码计划额度：每个窗口映射为一条百分比限额
    ///
    /// 不含金额维度（`included` / `purchasedUSD` 均为 nil），UI 走既有「遗留计划」渲染分支，
    /// 由 `usedAmount` / `limitAmount` 补出 credits 明细。
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        let dto: OpenDesignCodingPlanDTO
        do {
            dto = try JSONDecoder().decode(OpenDesignCodingPlanDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        guard dto.eligible else {
            throw BillingError.forbidden("当前账号未开通编码计划")
        }
        let limits = dto.windows.map { window -> BillingPercentLimit in
            let used = window.usedCredits.flatMap { Double($0) }
            let limit = window.limitCredits.flatMap { Double($0) }
            // 服务端给了 remainingCredits 就用它，缺失时才按「上限 − 已用」推算
            let remaining = window.remainingCredits.flatMap { Double($0) }
                ?? limit.map { max($0 - (used ?? 0), 0) }
            // 重置时刻只解析一次：resetsAt 与 window.resetsAt 必须指向同一时刻
            let resetsAt = window.resetsAt.flatMap(parseISO8601)
            return BillingPercentLimit(id: window.policyId,
                                       title: windowTitle(durationSeconds: window.durationSeconds),
                                       // limitCredits 缺失 / 为 0 = 分母非法 → nil（不可得），
                                       // 该窗口渲染「—」而不是 0%（0% 会被读成「额度用光」）
                                       remainingFraction: remainingFraction(remaining: remaining, limit: limit),
                                       resetsAt: resetsAt,
                                       usedAmount: used,
                                       limitAmount: limit,
                                       unitLabel: "credits",
                                       window: quotaWindow(durationSeconds: window.durationSeconds,
                                                           resetsAt: resetsAt))
        }
        return BillingBalance(included: nil, purchasedUSD: nil, percentLimits: limits)
    }

    /// 剩余 credits / 上限 → 剩余比例（任一缺失或分母非正 → nil = 不可得）
    static func remainingFraction(remaining: Double?, limit: Double?) -> Double? {
        guard let remaining, let limit, limit > 0, remaining.isFinite, limit.isFinite else { return nil }
        return min(max(remaining / limit, 0), 1)
    }

    /// 窗口时长 + 重置时刻 → 领域窗口（缺任一要素则为 nil）
    ///
    /// 种类按服务端给的 `durationSeconds` 推断（18000 → 会话、604800 → 每周、30 天 → 每月），
    /// 与 `BillingQuotaWindow.kind(forDuration:)` 同一口径；恢复通知据此区分窗口周期。
    /// 接口不保证下发时长，缺时长时退回「无窗口」（宁可不区分周期，也不编造时长）。
    static func quotaWindow(durationSeconds: Double?, resetsAt: Date?) -> BillingQuotaWindow? {
        guard let duration = durationSeconds, duration > 0, let resetsAt else { return nil }
        return BillingQuotaWindow(kind: BillingQuotaWindow.kind(forDuration: duration),
                                  duration: duration,
                                  resetsAt: resetsAt)
    }

    /// 解析用量响应（只读顶层聚合，不碰 entries）
    public static func decodeUsageSummary(from data: Data, requestedRange: BillingRange,
                                          window: DateInterval) throws -> (totals: BillingMetrics,
                                                                           runtimes: [String]) {
        let dto: OpenDesignUsageDTO
        do {
            dto = try JSONDecoder().decode(OpenDesignUsageDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        return (dto.metrics, dto.filterOptions?.runtimes ?? [])
    }

    /// 只解析顶层聚合指标（按模型查询复用）
    public static func decodeUsageTotals(from data: Data) throws -> BillingMetrics {
        let dto: OpenDesignUsageDTO
        do {
            dto = try JSONDecoder().decode(OpenDesignUsageDTO.self, from: data)
        } catch {
            throw BillingError.invalidResponse(error.localizedDescription)
        }
        return dto.metrics
    }

    // MARK: - 时间格式

    /// 时间范围 → 查询窗口（本地时区自然日 / 自然小时边界，与服务端 UTC 时间点对齐）
    public static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// ISO8601 解析（兼容带/不带小数秒）
    static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    /// 窗口时长 → 展示名称（18000 秒 = 5 小时、604800 秒 = 每周，其余按小时/天推导）
    public static func windowTitle(durationSeconds: Double?) -> String {
        guard let duration = durationSeconds, duration > 0 else { return "编码计划" }
        let hours = duration / 3_600
        if hours >= 168, abs(hours.truncatingRemainder(dividingBy: 168)) < 0.5 { return "每周" }
        if hours >= 24, abs(hours.truncatingRemainder(dividingBy: 24)) < 0.5 {
            return "\(Int((hours / 24).rounded())) 天"
        }
        if abs(hours.rounded() - hours) < 0.5 { return "\(Int(hours.rounded())) 小时" }
        return "\(Int(hours.rounded())) 小时"
    }
}
