import Foundation

// MARK: - 空态文案（纯逻辑，可单测）

/// 空态原因 —— 由数据层判定（快照只含可见项时，视图不知道「为什么一个都没有」）
public enum BillingEmptyReason: Equatable {
    /// 注册表里一个 provider 都没有
    case noProviderRegistered
    /// 有 provider，但全部未配置凭据
    case allUnconfigured
    /// 有 provider，但全部被停用
    case allDisabled
    /// 其它 / 未知（数据层没给原因时）
    case unknown
}

/// 空态文案
public struct BillingEmptyCopy: Equatable {
    public let title: String
    public let hint: String
    public let action: String

    public init(title: String, hint: String, action: String) {
        self.title = title
        self.hint = hint
        self.action = action
    }
}

public enum BillingEmptyStateLogic {

    /// 按原因给文案（按钮文案恒定「去设置配置」，因为它总是打开同一页）
    public static func copy(for reason: BillingEmptyReason) -> BillingEmptyCopy {
        switch reason {
        case .noProviderRegistered:
            return BillingEmptyCopy(title: "还没有额度 Provider",
                                    hint: "应用内没有注册任何额度 Provider。\n可在「设置 › 额度 Provider」查看可用项。",
                                    action: "打开设置")
        case .allUnconfigured:
            return BillingEmptyCopy(title: "还没有可查询的额度 Provider",
                                    hint: "已注册的 Provider 尚未配置凭据。\n在「设置 › 额度 Provider」里填入凭据后，这里会显示剩余额度。",
                                    action: "去设置配置")
        case .allDisabled:
            return BillingEmptyCopy(title: "额度 Provider 已全部停用",
                                    hint: "在「设置 › 额度 Provider」里重新启用需要的 Provider。",
                                    action: "去设置启用")
        case .unknown:
            return BillingEmptyCopy(title: "还没有可查询的额度 Provider",
                                    hint: "在「设置 › 额度 Provider」里启用并填入凭据后，\n这里会显示各家的剩余额度。",
                                    action: "去设置配置")
        }
    }
}
