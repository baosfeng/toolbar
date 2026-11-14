#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 额度页可见性取证（仅 DEBUG）

/// 额度页「未配置 provider 隐藏」的离屏取证 — 走**真实数据层契约**而不是版面注入
///
/// 与 `MenuPanelSnapshot+CreditsStates` 的差别：那边调 `injectPreview` 直接塞状态，
/// 绕过了 `BillingMonitor.emit()` 的过滤；这里按真实链路构造完整状态列表，
/// 再经 `BillingMonitor.Snapshot.make(from:enabledProviderCount:)` 过滤后喂给视图，
/// 因此截图证明的是「数据层过滤生效、视图只渲染可见项」。
///
/// 触发：`NM_SNAPSHOT_DIR=/tmp/xx NM_BILLING_MOCK=1 <bundle 内可执行>`（自动随主快照流程跑）
extension MenuPanelSnapshot {

    /// 三种组合各出浅色 / 深色两张
    /// - `mixed`：3 个 provider，2 个未配置 → 额度页只剩 1 块
    /// - `all-unconfigured`：3 个全未配置 → 整页空态（有说明 + 去设置配置入口）
    /// - `all-configured`：3 个全配置 → 3 块（对照，证明不是「一律只显示一块」）
    static func captureBillingVisibility(directory: URL) {
        let cases: [(suffix: String, configured: [Bool])] = [
            ("visibility-mixed", [true, false, false]),
            ("visibility-all-unconfigured", [false, false, false]),
            ("visibility-all-configured", [true, true, true]),
        ]
        for item in cases {
            let panel = MenuPanelView.evidencePanel()
            let states = item.configured.enumerated().map { index, configured in
                makeState(index: index, isConfigured: configured)
            }
            panel.billingPane.update(BillingMonitor.Snapshot.make(from: states,
                                                              enabledProviderCount: states.count))
            panel.select(tab: .credits)
            let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                render(view: panel, size: size, appearanceName: appearance,
                       to: directory.appendingPathComponent(
                            "menu-credits-\(item.suffix)\(unitFileSuffix)-\(name).png"))
            }
        }
    }

    /// 构造一个 provider 状态（字段与真实 provider 返回一致，未配置时无数据）
    private static func makeState(index: Int, isConfigured: Bool) -> BillingMonitor.ProviderState {
        let specs: [(id: String, name: String, symbol: String)] = [
            ("ollama", "Ollama", "cloud"),
            ("open-design", "Open Design", "paintpalette"),
            ("opencode-go", "OpenCode Go", "terminal"),
        ]
        let spec = specs[min(index, specs.count - 1)]
        let descriptor = BillingMonitor.ProviderDescriptor(
            id: spec.id, displayName: spec.name, symbolName: spec.symbol,
            credentialHint: "\(spec.name) API Key", supportsModelBreakdown: true)
        let now = Date()
        return BillingMonitor.ProviderState(
            descriptor: descriptor,
            range: .last24Hours,
            isConfigured: isConfigured,
            balance: isConfigured ? BillingBalance(
                included: BillingIncludedBalance(remainingUSD: 72.5, allowanceUSD: 100),
                purchasedUSD: 25,
                percentLimits: [BillingPercentLimit(id: "session", title: "会话",
                                                    remainingFraction: 0.95, resetsAt: now),
                                BillingPercentLimit(id: "weekly", title: "每周",
                                                    remainingFraction: 0.42, resetsAt: now)]) : nil,
            usage: isConfigured ? BillingUsage(
                range: .last24Hours, granularity: .hour,
                start: now.addingTimeInterval(-24 * 3_600), end: now,
                totals: BillingMetrics(requestCount: 15, usageUSD: 0.01718,
                                       inputTokens: 106_000, cachedInputTokens: 46_000,
                                       outputTokens: 13_600),
                buckets: []) : nil,
            lastUpdated: isConfigured ? now : nil,
            isLoading: false,
            errorMessage: nil)
    }
}
#endif
