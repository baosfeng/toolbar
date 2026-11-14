import Foundation

// MARK: - Cursor 订阅额度响应

/// 金额/用量块（单位：分）
struct CursorAmountDTO: Decodable {
    let used: Int?
    let limit: Int?
}

/// 计划用量块（含服务端已算好的百分比）
struct CursorPlanDTO: Decodable {
    let used: Int?
    let limit: Int?
    let totalPercentUsed: Double?
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?

    enum CodingKeys: String, CodingKey {
        case used
        case limit
        case totalPercentUsed
        case autoPercentUsed
        case apiPercentUsed
    }
}

/// 个人用量（计划 / 统筹上限 / 按量付费）
struct CursorIndividualUsageDTO: Decodable {
    let plan: CursorPlanDTO?
    let overall: CursorAmountDTO?
    let onDemand: CursorAmountDTO?
}

/// 团队用量（共享池 / 按量付费）
struct CursorTeamUsageDTO: Decodable {
    let pooled: CursorAmountDTO?
    let onDemand: CursorAmountDTO?
}

/// `GET https://cursor.com/api/usage-summary` 响应（非公开端点）
struct CursorUsageSummaryDTO: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let limitType: String?
    let isUnlimited: Bool?
    let individualUsage: CursorIndividualUsageDTO?
    let teamUsage: CursorTeamUsageDTO?
}

// MARK: - 解码

/// Cursor 额度解码 —— 纯函数，供 provider 与 TestRunner 共用
///
/// 接口形态来自社区实现（CodexBar `CursorUsageSummary`，非 Cursor 公开文档）；
/// 金额字段单位是**分**，展示时换算成美元（`unitLabel = "USD"`）。
public enum CursorBillingDecoding {

    /// 无限制角标
    public static let unlimitedBadge = "无限制"

    /// 解析额度响应
    ///
    /// 主窗口优先级：个人统筹上限（`individualUsage.overall`）> 计划（`individualUsage.plan`）
    /// > 团队共享池（`teamUsage.pooled`）；按量付费单独成一行。
    public static func decodeBalance(from data: Data) throws -> BillingBalance {
        guard let dto = try? JSONDecoder().decode(CursorUsageSummaryDTO.self, from: data) else {
            throw BillingError.invalidResponse("响应不是合法的 Cursor 额度 JSON（接口可能已变更）")
        }
        let window = window(from: dto)
        var limits: [BillingPercentLimit] = []
        if let main = mainLimit(dto: dto, window: window) { limits.append(main) }
        if let onDemand = onDemandLimit(dto: dto) { limits.append(onDemand) }
        guard !limits.isEmpty else {
            throw BillingError.invalidResponse("响应里没有额度数据（接口可能已变更）")
        }
        return BillingBalance(percentLimits: limits)
    }

    /// 计费周期 → 月窗口（起始缺失时按 30 天推算）
    static func window(from dto: CursorUsageSummaryDTO) -> BillingQuotaWindow? {
        guard let end = dto.billingCycleEnd.flatMap(BillingISO8601.parse) else { return nil }
        let start = dto.billingCycleStart.flatMap(BillingISO8601.parse)
        let duration = start.map { max(end.timeIntervalSince($0), 86_400) } ?? 86_400 * 30
        return BillingQuotaWindow(kind: .monthly, duration: duration, resetsAt: end)
    }

    /// 主窗口（计划 / 统筹 / 团队池）
    static func mainLimit(dto: CursorUsageSummaryDTO,
                          window: BillingQuotaWindow?) -> BillingPercentLimit? {
        if dto.isUnlimited == true {
            return BillingPercentLimit(id: "cursor-plan", title: "本月", remainingFraction: 1,
                                       resetsAt: window?.resetsAt, badge: unlimitedBadge,
                                       window: window)
        }
        if let overall = dto.individualUsage?.overall,
           let used = overall.used, let limit = overall.limit, limit > 0 {
            return amountLimit(id: "cursor-plan", title: "个人额度", used: used, limit: limit,
                               window: window)
        }
        if let plan = dto.individualUsage?.plan,
           let percent = planPercent(plan) {
            let resetAt = window?.resetsAt
            return BillingPercentLimit(id: "cursor-plan", title: "本月",
                                       remainingFraction: BillingPercentMath.remainingFraction(usedPercent: percent),
                                       resetsAt: resetAt,
                                       usedAmount: plan.used.map { Double($0) / 100 },
                                       limitAmount: plan.limit.map { Double($0) / 100 },
                                       unitLabel: "USD",
                                       window: window)
        }
        if let pooled = dto.teamUsage?.pooled,
           let used = pooled.used, let limit = pooled.limit, limit > 0 {
            return amountLimit(id: "cursor-plan", title: "团队池", used: used, limit: limit,
                               window: window)
        }
        return nil
    }

    /// 计划已用百分比：优先 `totalPercentUsed`，其次 auto + api
    static func planPercent(_ plan: CursorPlanDTO) -> Double? {
        if let total = plan.totalPercentUsed { return total }
        switch (plan.autoPercentUsed, plan.apiPercentUsed) {
        case let (auto?, api?): return auto + api
        case let (auto?, nil): return auto
        case let (nil, api?): return api
        default: return nil
        }
    }

    /// 按量付费（仅上限为正时展示）
    static func onDemandLimit(dto: CursorUsageSummaryDTO) -> BillingPercentLimit? {
        if let onDemand = dto.individualUsage?.onDemand,
           let used = onDemand.used, let limit = onDemand.limit, limit > 0 {
            return amountLimit(id: "cursor-on-demand", title: "按量付费", used: used, limit: limit,
                               window: nil)
        }
        if let teamOnDemand = dto.teamUsage?.onDemand,
           let used = teamOnDemand.used, let limit = teamOnDemand.limit, limit > 0 {
            return amountLimit(id: "cursor-on-demand", title: "按量付费", used: used, limit: limit,
                               window: nil)
        }
        return nil
    }

    /// 分值金额 → 百分比限额（分 → 美元）
    static func amountLimit(id: String, title: String, used: Int, limit: Int,
                            window: BillingQuotaWindow?) -> BillingPercentLimit {
        BillingPercentLimit(id: id, title: title,
                            remainingFraction: BillingPercentMath.remainingFraction(used: Double(used),
                                                                                   limit: Double(limit)),
                            resetsAt: window?.resetsAt,
                            usedAmount: Double(used) / 100,
                            limitAmount: Double(limit) / 100,
                            unitLabel: "USD",
                            window: window)
    }

    /// 把用户输入整理成 Cookie 头
    ///
    /// 两种输入都接受：只给 token 值 → 拼成 `WorkosCursorSessionToken=…`；
    /// 给整条 Cookie（含 `=`）→ 原样使用。
    public static func cookieHeader(from raw: String) -> String {
        let value = BillingCredentialNormalizer.token(raw)
        guard !value.isEmpty else { return "" }
        return value.contains("=") ? value : "WorkosCursorSessionToken=\(value)"
    }

    /// HTTP 状态码 → 领域错误（401 / 403 给「凭据失效」类明确文案）
    public static func mapHTTPError(statusCode: Int, retryAfter: TimeInterval?,
                                    message: String?) -> BillingError {
        switch statusCode {
        case 400:
            return .invalidRequest(message ?? "请求参数有误（接口可能已变更）")
        case 401:
            return .unauthorized
        case 403:
            return .forbidden("Cookie 已失效或账号无权读取用量，请重新登录 cursor.com 后更新 Cookie")
        case 429:
            return .rateLimited(retryAfter: retryAfter)
        case 500...599:
            return .serviceUnavailable(message)
        default:
            return .invalidResponse("HTTP \(statusCode)")
        }
    }
}
