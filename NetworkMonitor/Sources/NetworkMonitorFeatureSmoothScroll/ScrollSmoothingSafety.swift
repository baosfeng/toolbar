import Foundation

// MARK: - 安全闸（kill switch / tap 健康度 / 引擎状态）

/// 排障开关 —— 环境变量硬关闭
///
/// `NM_SCROLL_SMOOTHING_DISABLE=1` 时引擎完全不装 tap：即便偏好是开、
/// 即便辅助功能权限在，也不会碰全局输入路径。用于现场排障（怀疑是它导致滚动异常）
/// 与「先关掉再说」的兜底，不写偏好、不影响下次启动。
public enum ScrollSmoothingKillSwitch {

    public static let environmentKey = "NM_SCROLL_SMOOTHING_DISABLE"

    /// 是否被环境变量关闭（1 / true / yes 均视为关；其余一律不关）
    public static func isDisabled(environment: [String: String]) -> Bool {
        guard let raw = environment[environmentKey] else { return false }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }
}

// MARK: - tap 健康度

/// tap 被系统禁用后的处置
public enum ScrollTapDisableAction: Equatable, Sendable {
    /// 重新启用 tap
    case reenable
    /// 连续禁用已达上限：整个功能自动停用（系统滚动恢复原样）
    case giveUp
}

/// tap 连续禁用计数器 —— 纯状态机
///
/// 背景：事件 tap 的回调超时或用户输入异常时，系统会直接禁用 tap 并投递
/// `tapDisabledByTimeout` / `tapDisabledByUserInput`。一条被禁用却没人重新启用的 tap
/// 会让「滚动完全不响应」——比不平滑糟得多。所以策略是：先重启用（1、2 次），
/// 连续到第 3 次就判定这台机器上它不稳定，**停用整个功能**并记 error，
/// 把全局输入路径还给系统。
///
/// 「连续」的判定：只有真正处理过一条滚轮事件才算恢复健康（`recordHealthyEvent`）；
/// 仅仅「时间过去了」不算——否则反复超时的 tap 永远凑不满 3 次。
public struct ScrollTapHealth: Equatable, Sendable {

    /// 连续禁用多少次后自动停用
    public static let maximumConsecutiveDisables = 3

    /// 当前连续禁用次数
    public private(set) var consecutiveDisables = 0

    public init() {}

    /// 记录一次系统禁用，返回处置动作
    public mutating func recordDisable() -> ScrollTapDisableAction {
        consecutiveDisables += 1
        return consecutiveDisables >= Self.maximumConsecutiveDisables ? .giveUp : .reenable
    }

    /// 记录一次「真的处理了滚轮事件」——tap 工作正常，计数清零
    public mutating func recordHealthyEvent() {
        consecutiveDisables = 0
    }
}

// MARK: - 引擎状态

/// 引擎对外状态（设置页据此显示一行说明，不含易变字段）
public enum ScrollSmoothingEngineState: Equatable, Sendable {
    /// 未运行（功能关闭 / 尚未启动）
    case idle
    /// 运行中：tap 已装、按偏好平滑
    case running
    /// 被环境变量 `NM_SCROLL_SMOOTHING_DISABLE` 硬关闭
    case disabledByEnvironment
    /// 无法创建事件 tap（通常是没给「辅助功能」权限）
    case tapUnavailable
    /// tap 连续被系统禁用，已自动停用整个功能
    case stoppedAfterRepeatedDisables

    /// 设置页的一行说明
    public var displayText: String {
        switch self {
        case .idle:
            return "未启用"
        case .running:
            return "已启用：仅平滑纯鼠标滚轮"
        case .disabledByEnvironment:
            return "已被环境变量 NM_SCROLL_SMOOTHING_DISABLE 关闭"
        case .tapUnavailable:
            return "无法建立事件 tap：请在「系统权限」页授予「辅助功能」"
        case .stoppedAfterRepeatedDisables:
            return "事件 tap 连续被系统禁用，已自动停用（滚动恢复原样）"
        }
    }
}
