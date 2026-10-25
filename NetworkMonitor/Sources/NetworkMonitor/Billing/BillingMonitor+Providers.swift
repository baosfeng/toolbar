import Foundation
import NetworkMonitorCore

// MARK: - 计费状态管理器（provider 启用状态）

/// 启用开关与状态重建 — 从 `BillingMonitor.swift` 拆出（主文件新增该能力后超过 15 KiB 上限）
///
/// 语义：停用 = 不查询、不出现在额度页，但**不删凭据**；重新启用时从凭据存储重新判断配置态。
/// 跨文件访问的 `emit` 由 private 放宽为 internal。
extension BillingMonitor {

    /// 切换启用状态 — 停用后不查询、不出现在额度页；启用后重建状态并强制刷新一次
    ///
    /// 停用不移除凭据：重新启用时 `isConfigured` 仍由凭据存储决定，余额 / 用量从零开始
    /// （停用期间没有新数据，沿用旧值会展示过期额度）。
    func setProviderEnabled(_ enabled: Bool, providerID: String) {
        guard registry.provider(id: providerID) != nil else { return }
        preferences.setEnabled(enabled, for: providerID)
        // 用户刚操作完：重置该 provider 的节流基准，启用时立即查询
        lastAttempts[providerID] = nil
        if !enabled {
            // 作废在途结果：代次递增后，旧响应在 apply 里被判过期丢弃
            _ = nextGeneration(for: providerID)
        }
        rebuildStates()
        emit()
        guard enabled else { return }
        refresh(force: true)
    }

    /// 由 provider 协议实例生成初始展示状态（配置态由凭据存储决定）
    static func makeState(for provider: any BillingProvider,
                          credentialStore: any BillingCredentialStore) -> ProviderState {
        let descriptor = ProviderDescriptor(id: provider.id,
                                            displayName: provider.displayName,
                                            symbolName: provider.symbolName,
                                            credentialHint: provider.credentialHint,
                                            supportsModelBreakdown: provider.supportsModelBreakdown,
                                            supportsUsage: provider.supportsUsage,
                                            supportsTimeSeries: provider.supportsTimeSeries,
                                            credentialPageURL: provider.credentialPageURL)
        return ProviderState(descriptor: descriptor,
                             range: .last24Hours,
                             isConfigured: credentialStore.credential(for: provider.id) != nil,
                             balance: nil,
                             usage: nil,
                             lastUpdated: nil,
                             isLoading: false,
                             errorMessage: nil)
    }

    /// 按启用偏好重建 states — 仍在启用列表中的 provider 保留运行时数据
    private func rebuildStates() {
        var existing: [String: ProviderState] = [:]
        for state in states { existing[state.descriptor.id] = state }
        let enabledIDs = BillingProviderPreferences.filterEnabled(registry.all.map { $0.id },
                                                                  preferences: preferences)
        states = enabledIDs.compactMap { id in
            guard let provider = registry.provider(id: id) else { return nil }
            return existing[id] ?? Self.makeState(for: provider, credentialStore: credentialStore)
        }
        // 停用者的节流基准一并清掉：重新启用时不应继承旧的「上次刷新」时间
        let enabled = Set(enabledIDs)
        lastAttempts = lastAttempts.filter { enabled.contains($0.key) }
        // 代次只增不减：删键会让重新启用后的新请求代次回卷，旧在途响应可能覆盖新状态
    }
}
