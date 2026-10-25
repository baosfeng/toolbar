import Foundation
import NetworkMonitorCore

// MARK: - 额度页快照

/// 快照结构 — 每个已注册 provider 各持一份状态，供「额度」tab 一次展示全部
///
/// 拆分原因：`BillingMonitor` 主体接近单文件 15 KiB 上限，数据结构独立成文件；
/// 成员为 `internal`，供同模块 UI 与状态管理器共用。
extension BillingMonitor {

    /// provider 展示信息 — UI 只读，避免直接持有 provider 协议实例
    struct ProviderDescriptor: Equatable {
        /// 稳定标识（凭据键）
        let id: String
        /// 展示名称
        let displayName: String
        /// SF Symbol 图标名（禁止 emoji）
        let symbolName: String
        /// 凭据输入框占位文案
        let credentialHint: String
        /// 是否提供按模型分组的明细
        let supportsModelBreakdown: Bool
        /// 是否支持时间序列（false 时 UI 隐藏趋势图）
        let supportsTimeSeries: Bool
        /// 是否提供用量明细（false 时 UI 隐藏用量区与摘要行）
        let supportsUsage: Bool
        /// 凭据获取页面（配置态链接跳转目标；nil = 无在线入口）
        let credentialPageURL: URL?

        /// 兼容默认值（快照示意数据 / 测试构造用）
        init(id: String, displayName: String, symbolName: String, credentialHint: String,
             supportsModelBreakdown: Bool, supportsUsage: Bool = true, supportsTimeSeries: Bool = true,
             credentialPageURL: URL? = nil) {
            self.id = id
            self.displayName = displayName
            self.symbolName = symbolName
            self.credentialHint = credentialHint
            self.supportsModelBreakdown = supportsModelBreakdown
            self.supportsUsage = supportsUsage
            self.supportsTimeSeries = supportsTimeSeries
            self.credentialPageURL = credentialPageURL
        }
    }
    /// 单个 provider 的展示状态
    struct ProviderState {
        /// provider 展示信息（名称 / 图标 / 能力位）
        let descriptor: ProviderDescriptor
        /// 该 provider 的用量时间范围（各自独立选择）
        var range: BillingRange
        /// 是否已配置凭据
        var isConfigured: Bool
        /// 余额（nil = 尚无成功数据）
        var balance: BillingBalance?
        /// 用量（nil = 尚无成功数据）
        var usage: BillingUsage?
        /// 最近一次成功刷新时间
        var lastUpdated: Date?
        /// 是否正在请求
        var isLoading: Bool
        /// 错误文案（失败时保留上次成功数据）
        var errorMessage: String?
    }

    /// 面板快照 — 全部 provider 状态（按注册顺序）
    struct Snapshot {
        var states: [ProviderState]

        /// 注册表为空（面板整页空态）
        var hasNoProvider: Bool { states.isEmpty }

        /// 按 id 取状态
        func state(for providerID: String) -> ProviderState? {
            states.first { $0.descriptor.id == providerID }
        }
    }

    /// 单个 provider 的一次并发拉取结果（跨 actor 传递用，`Sendable`）
    struct ProviderFetchResult: Sendable {
        let id: String
        let balance: BillingOutcome<BillingBalance>
        /// 用量结果（nil = provider 不支持用量明细，未发起请求）
        let usage: BillingOutcome<BillingUsage>?
    }
}