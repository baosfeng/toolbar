import Foundation
import NetworkMonitorCore

// MARK: - 额度页快照

/// 快照结构 — 每个已注册 provider 各持一份状态，供「额度」tab 一次展示全部
///
/// 拆分原因：`BillingMonitor` 主体接近单文件 15 KiB 上限，数据结构独立成文件；
/// 类型与只读字段为 public：App 的额度页 / 设置页跨模块读，写入仍只走状态管理器。
extension BillingMonitor {

    /// provider 展示信息 — UI 只读，避免直接持有 provider 协议实例
    public struct ProviderDescriptor: Equatable {
        /// 稳定标识（**实例标识**：默认实例 = kindID，命名实例 = `kindID::slug`）
        public let id: String
        /// provider 类型标识（同一类型可有多实例；UI 用来分组）
        public let kindID: String
        /// 命名实例后缀（默认实例为 nil；设置页据此决定是否显示「重命名 / 删除」）
        public let instanceLabel: String?
        /// 展示名称（含实例名）
        public let displayName: String
        /// SF Symbol 图标名（禁止 emoji）
        public let symbolName: String
        /// 凭据输入框占位文案
        public let credentialHint: String
        /// 是否提供按模型分组的明细
        public let supportsModelBreakdown: Bool
        /// 是否支持时间序列（false 时 UI 隐藏趋势图）
        public let supportsTimeSeries: Bool
        /// 是否提供用量明细（false 时 UI 隐藏用量区与摘要行）
        public let supportsUsage: Bool
        /// 支持查询的用量范围（UI 只渲染这些范围按钮）
        public let supportedRanges: [BillingRange]
        /// 凭据获取页面（配置态链接跳转目标；nil = 无在线入口）
        public let credentialPageURL: URL?

        /// 兼容默认值（快照示意数据 / 测试构造用）
        ///
        /// `kindID` 缺省等于 `id`（默认实例）；`instanceLabel` 缺省 nil。
        public init(id: String, kindID: String? = nil, instanceLabel: String? = nil,
                    displayName: String, symbolName: String, credentialHint: String,
                    supportsModelBreakdown: Bool, supportsUsage: Bool = true, supportsTimeSeries: Bool = true,
                    supportedRanges: [BillingRange] = BillingRange.allCases,
                    credentialPageURL: URL? = nil) {
            self.id = id
            self.kindID = kindID ?? id
            self.instanceLabel = instanceLabel
            self.displayName = displayName
            self.symbolName = symbolName
            self.credentialHint = credentialHint
            self.supportsModelBreakdown = supportsModelBreakdown
            self.supportsUsage = supportsUsage
            self.supportsTimeSeries = supportsTimeSeries
            self.supportedRanges = supportedRanges
            self.credentialPageURL = credentialPageURL
        }
    }
    /// 单个 provider 的展示状态
    public struct ProviderState {
        /// provider 展示信息（名称 / 图标 / 能力位）
        public let descriptor: ProviderDescriptor
        /// 该 provider 的用量时间范围（各自独立选择）
        public var range: BillingRange
        /// 是否已配置凭据
        public var isConfigured: Bool
        /// 余额（nil = 尚无成功数据）
        public var balance: BillingBalance?
        /// 用量（nil = 尚无成功数据）
        public var usage: BillingUsage?
        /// 最近一次成功刷新时间
        public var lastUpdated: Date?
        /// 是否正在请求
        public var isLoading: Bool
        /// 错误文案（失败时保留上次成功数据）
        public var errorMessage: String?

        /// 供 App 层构造展示状态（示意数据 / 快照取证）与测试直接构造可见性样本
        public init(descriptor: ProviderDescriptor, range: BillingRange, isConfigured: Bool,
                    balance: BillingBalance?, usage: BillingUsage?, lastUpdated: Date?,
                    isLoading: Bool, errorMessage: String?) {
            self.descriptor = descriptor
            self.range = range
            self.isConfigured = isConfigured
            self.balance = balance
            self.usage = usage
            self.lastUpdated = lastUpdated
            self.isLoading = isLoading
            self.errorMessage = errorMessage
        }
    }

    /// 面板快照 — **只含额度页可见的 provider**（按注册顺序）
    ///
    /// 「可见」= 已启用且已配置凭据（判据在 Core 的 `BillingVisibilityRule`）：
    /// 用户要求「没有配置的需要隐藏」，所以未配置的 provider 根本不出现在 `states` 里，
    /// 额度页视图不需要写任何过滤（视图层由视觉任务独占，判据必须留在数据层）。
    /// 停用的 provider 更早一步就被 `BillingMonitor.rebuildStates` 排除。
    public struct Snapshot {
        /// 额度页要渲染的状态（已配置 + 已启用；空数组 = 整页空态）
        public var states: [ProviderState]
        /// 已启用（但可能未配置）的 provider 总数 —— 用于区分两种空态
        public var enabledProviderCount: Int = 0
        /// 是否因锁屏 / 休眠暂停了后台刷新（面板据此显示暂停态，而不是装作在查询）
        public var isPaused: Bool = false

        /// 供 App 层构造快照（示意数据 / 快照取证）与测试构造空态样本
        public init(states: [ProviderState], enabledProviderCount: Int = 0, isPaused: Bool = false) {
            self.states = states
            self.enabledProviderCount = enabledProviderCount
            self.isPaused = isPaused
        }

        /// 整页空态的原因
        public var emptyReason: BillingEmptyReason? {
            guard states.isEmpty else { return nil }
            return enabledProviderCount == 0 ? .noEnabledProvider : .noneConfigured
        }

        /// 是否整页空态
        public var isEmpty: Bool { states.isEmpty }

        /// 按 id 取状态
        public func state(for providerID: String) -> ProviderState? {
            states.first { $0.descriptor.id == providerID }
        }

        /// 从全部已启用 provider 的状态构造额度页快照 —— **可见性过滤的唯一入口**
        ///
        /// 过滤规则来自 Core 的 `BillingVisibilityRule`（已启用 + 已配置才可见）。
        /// 视图层不需要也不应该再写过滤：`MenuPanel` 由视觉改造任务独占，
        /// 判据放在这里才能保证改视图不会把「隐藏未配置」这条行为改丢。
        ///
        /// - Parameters:
        ///   - states: 全部已启用 provider 的运行时状态（可能含未配置的）
        ///   - enabledProviderCount: 已启用 provider 总数（区分两种空态）
        /// - Returns: 只保留可见那些，`enabledProviderCount` 原样记录
        /// - Parameter isPaused: 后台刷新是否处于暂停态（锁屏 / 休眠）
        public static func make(from states: [ProviderState], enabledProviderCount: Int,
                                isPaused: Bool = false) -> Snapshot {
            Snapshot(states: BillingVisibilityRule.visibleEntries(
                        states,
                        isConfigured: { $0.isConfigured },
                        isEnabled: { _ in true }),
                     enabledProviderCount: enabledProviderCount,
                     isPaused: isPaused)
        }
    }

    /// 额度页空态分类 — 两类空态文案不同（第二类必须给「去设置配置」入口）
    public enum BillingEmptyReason: Equatable {
        /// 一个启用的 provider 都没有（注册表为空 / 全部停用）：去设置页启用
        case noEnabledProvider
        /// 有启用的 provider 但都没有凭据：去设置页填 Key
        case noneConfigured
    }

    /// 单个 provider 的一次并发拉取结果（跨 actor 传递用，`Sendable`）
    struct ProviderFetchResult: Sendable {
        let id: String
        let balance: BillingOutcome<BillingBalance>
        /// 用量结果（nil = provider 不支持用量明细，未发起请求）
        let usage: BillingOutcome<BillingUsage>?
    }
}