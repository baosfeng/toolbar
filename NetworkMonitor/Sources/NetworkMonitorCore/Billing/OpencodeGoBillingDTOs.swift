import Foundation

// MARK: - OpenCode Go 响应 DTO

/// 三窗口定义 — 取值顺序即展示顺序（5 小时 → 每周 → 每月）
///
/// id 用 window:<rawValue>：稳定标识，窗口顺序或标题变化都不会让阈值提醒状态错位。
enum OpencodeGoWindow: String, CaseIterable, Sendable {
    case rolling
    case weekly
    case monthly

    /// 稳定标识（UI 排序与提醒状态键）
    var limitID: String { "window:\(rawValue)" }

    /// 展示名称
    var title: String {
        switch self {
        case .rolling: return "5 小时"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    /// 额度窗口种类（恢复通知据此区分「会话窗口重置」与「周 / 月额度重置」）
    var windowKind: BillingWindowKind {
        switch self {
        case .rolling: return .session
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }

    /// 窗口真实时长（秒）：5 小时 / 7 天 / 30 天
    ///
    /// 接口不返回时长，按官方公布的三档窗口常量声明；与重置时刻一起构成
    /// `BillingQuotaWindow`，让周期标识（cycleID）可跨刷新稳定比对。
    var windowDuration: TimeInterval {
        switch self {
        case .rolling: return 18_000
        case .weekly: return 604_800
        case .monthly: return 2_592_000
        }
    }

    /// 构造领域窗口：重置时刻由调用方按同一份响应解析后传入
    ///
    /// 与 `resetsAt` 用同一个 Date 实例，保证「有窗口时两者指向同一时刻」的契约；
    /// 缺重置字段时调用方不构造窗口（nil），回落为仅百分比限额。
    func quotaWindow(resetsAt: Date) -> BillingQuotaWindow {
        BillingQuotaWindow(kind: windowKind, duration: windowDuration, resetsAt: resetsAt)
    }
}

/// 单个额度窗口 — 新旧两套字段名并存
///
/// 新形态：{"percent": 12.5, "resetsAt": "2026-10-25T12:00:00Z", "status": "ok"}
/// 旧形态（2026-08 前后）：{"usagePercent": 12.5, "resetInSec": 3600}
/// 所有字段可选：缺比例的窗口整条跳过，不影响其它窗口。
struct OpencodeGoWindowDTO: Decodable {
    /// 已用比例 0–100（新键名）
    let percent: Double?
    /// 已用比例 0–100（旧键名）
    let usagePercent: Double?
    /// 重置时刻 RFC3339（新键名）
    let resetsAt: String?
    /// 距重置的剩余秒数（旧键名，需按基准时刻换算成绝对时刻）
    let resetInSec: Double?
    /// 窗口状态：ok / rate-limited（后者表示该窗口已耗尽）
    let status: String?

    /// 已用比例（新旧键名任一存在即可）
    var usedPercent: Double? { percent ?? usagePercent }
}

/// 三窗口集合 — 同时用于新形态的 usage 子对象与旧形态的顶层平铺结构
struct OpencodeGoWindowScopeDTO: Decodable {
    let rolling: OpencodeGoWindowDTO?
    let rollingUsage: OpencodeGoWindowDTO?
    let weekly: OpencodeGoWindowDTO?
    let weeklyUsage: OpencodeGoWindowDTO?
    let monthly: OpencodeGoWindowDTO?
    let monthlyUsage: OpencodeGoWindowDTO?

    /// 取指定窗口（新键名优先，旧键名兜底）
    func window(for window: OpencodeGoWindow) -> OpencodeGoWindowDTO? {
        switch window {
        case .rolling: return rolling ?? rollingUsage
        case .weekly: return weekly ?? weeklyUsage
        case .monthly: return monthly ?? monthlyUsage
        }
    }
}

/// 额度响应包壳 — 官方当前把三窗口包在 usage 里
///
/// 旧形态没有这层包壳（三窗口直接平铺在顶层），所以解析时两处都尝试，
/// 见 OpencodeGoBillingProvider.decodeBalance(from:now:)。
struct OpencodeGoUsageResponseDTO: Decodable {
    let usage: OpencodeGoWindowScopeDTO?
}
