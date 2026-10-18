import AppKit
import NetworkMonitorCore

// MARK: - 额度页样式令牌

/// 额度页专用字号与色块 — 与原型 CSS 对齐；通用颜色仍走 `MenuPanelStyle`
@MainActor
enum BillingPaneStyle {
    /// hero 金额（25pt 等宽半粗）
    static let heroFont = NSFont.monospacedDigitSystemFont(ofSize: 25, weight: .semibold)
    /// provider 名称（12pt 半粗）
    static let providerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    /// 卡片小标题 / 分区标题（11pt 半粗）
    static let cardTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    /// 正文（11pt）
    static let labelFont = NSFont.systemFont(ofSize: 11)
    /// 金额 / 数值（11pt 等宽）
    static let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    /// 指标数值（12pt 等宽半粗）
    static let metricValueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    /// 说明与时间戳（10pt）
    static let subFont = NSFont.systemFont(ofSize: 10)
    /// 页头时间戳（10pt 等宽）
    static let stampFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 范围按钮（10pt 等宽）
    static let rangeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 范围按钮选中态（10pt 等宽半粗）
    static let rangeSelectedFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    /// 图表坐标轴（9pt 等宽）
    static let axisFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    /// 模型名（11pt 等宽）
    static let modelNameFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    /// 模型金额（11pt 等宽半粗）
    static let modelAmountFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    /// 模型请求数（10pt 等宽）
    static let modelRequestFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// 说明段落（10.5pt）
    static let noteFont = NSFont.systemFont(ofSize: 10.5)

    /// 强调色浅底（范围选中态 15%）
    static var accentSoft: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.15) }
    /// 强调色图标容器底（12%）
    static var accentTile: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.12) }
    /// 危险色浅底（错误条 10%）
    static var dangerSoft: NSColor { NSColor.systemRed.withAlphaComponent(0.10) }
    /// 1pt 浅分隔线（10% 前景色，深浅色自适应）
    static var hairline: NSColor { NSColor.labelColor.withAlphaComponent(0.10) }
    /// 输入框边框（分隔线色，深浅色自适应）
    static var fieldBorder: NSColor { NSColor.separatorColor }

    // MARK: - 动态文字色

    /// 次要文字色 — 视觉对齐 `MenuPanelStyle.secondaryText`，但用 dynamicProvider 在绘制时解析
    ///
    /// 后者由 `labelColor.withAlphaComponent(...)` 生成、颜色创建时固化，切换外观后会残留旧色（浅色下变白）。
    static let secondaryText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.88)
            : NSColor.black.withAlphaComponent(0.78)
    }

    /// 三级文字色 — 同为动态解析（视觉值对应 `MenuPanelStyle.tertiaryText`）
    static let tertiaryText = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.62)
            : NSColor.black.withAlphaComponent(0.55)
    }
}

// MARK: - 额度页

/// 额度页 — 页头（provider / 刷新）、余额卡、用量区、凭据配置态、错误条与空态
///
/// 数据由 `BillingMonitor` 通过 `update(_:)` 注入；本视图不直接访问网络或凭据存储。
/// 键盘可达行顺序：provider 切换（多 provider 时）→ 刷新 → 范围按钮 → 重试 / 保存 → 官网链接。
final class BillingPaneView: MenuPanelPaneView {

    // MARK: - 回调

    /// 点「刷新」（force 刷新）
    var onRefresh: (() -> Void)?
    /// 点错误条「重试」
    var onRetry: (() -> Void)?
    /// 切换用量范围
    var onRangeChange: ((BillingRange) -> Void)?
    /// 「保存并查询」提交 API Key
    var onSaveCredential: ((String) -> Void)?
    /// 「在 ollama.com 获取 API Key」
    var onOpenProviderSite: (() -> Void)?
    /// 多 provider 时切换 provider
    var onProviderChange: ((String) -> Void)?

    /// provider 官方 API Key 页面（由控制器打开）
    static let credentialPageURL = URL(string: "https://ollama.com/settings/keys")!

    // MARK: - 子视图

    private let emptyView = BillingEmptyView()
    private let headerView = BillingPageHeaderView()
    private let errorBanner = BillingErrorBannerView()
    private let balanceSection = BillingBalanceSectionView()
    private let usageSection = BillingUsageSectionView()
    private let setupView = BillingCredentialSetupView()
    private var snapshot: BillingMonitor.Snapshot?

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        headerView.onRefresh = { [weak self] in self?.onRefresh?() }
        headerView.onProviderTap = { [weak self] in self?.showProviderMenu() }
        errorBanner.onRetry = { [weak self] in self?.onRetry?() }
        usageSection.onRangeChange = { [weak self] range in self?.onRangeChange?(range) }
        setupView.onSave = { [weak self] key in self?.onSaveCredential?(key) }
        setupView.onOpenSite = { [weak self] in self?.onOpenProviderSite?() }

        emptyView.isHidden = true
        errorBanner.isHidden = true
        setupView.isHidden = true
        balanceSection.isHidden = true
        usageSection.isHidden = true

        let stack = NSStackView(views: [emptyView, headerView, errorBanner, balanceSection,
                                        usageSection, setupView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：强制悬停用量柱状图的某根柱
    func forceChartHoverForSnapshot(_ index: Int?) {
        usageSection.forceHoverForSnapshot(index)
    }
#endif

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        guard let snapshot, !snapshot.providers.isEmpty else { return [] }
        let showsProviderMenu = snapshot.providers.count > 1
        if !snapshot.isConfigured {
            var rows: [MenuPanelRow] = []
            if showsProviderMenu { rows.append(headerView.providerButtonRow) }
            rows.append(contentsOf: setupView.focusableRows)
            return rows
        }
        var rows: [MenuPanelRow] = []
        if showsProviderMenu { rows.append(headerView.providerButtonRow) }
        rows.append(headerView.refreshButtonRow)
        rows.append(contentsOf: usageSection.focusableRows)
        if !errorBanner.isHidden { rows.append(errorBanner.retryButtonRow) }
        return rows
    }

    // MARK: - 数据更新

    /// 应用最新快照（由控制器转发）
    func update(_ snapshot: BillingMonitor.Snapshot) {
        self.snapshot = snapshot
        let hasProvider = !snapshot.providers.isEmpty
        emptyView.isHidden = hasProvider
        headerView.isHidden = !hasProvider
        setupView.isHidden = !hasProvider || snapshot.isConfigured
        balanceSection.isHidden = !hasProvider || !snapshot.isConfigured
        usageSection.isHidden = !hasProvider || !snapshot.isConfigured

        let showsError = hasProvider && snapshot.isConfigured && snapshot.errorMessage != nil
        errorBanner.isHidden = !showsError
        if showsError, let message = snapshot.errorMessage {
            errorBanner.update(message: message)
        }

        headerView.update(provider: snapshot.currentProvider,
                          lastUpdated: snapshot.lastUpdated,
                          isLoading: snapshot.isLoading,
                          showsProviderMenu: snapshot.providers.count > 1)
        setupView.update(placeholder: snapshot.currentProvider?.credentialHint ?? "API Key")

        guard snapshot.isConfigured else { return }
        balanceSection.update(balance: snapshot.balance)
        usageSection.update(usage: snapshot.usage,
                            range: snapshot.range,
                            showsModelBreakdown: snapshot.currentProvider?.supportsModelBreakdown ?? false)
    }

    // MARK: - provider 切换菜单

    /// 多 provider 时点击页头名称弹出切换菜单（单 provider 时不显示入口）
    private func showProviderMenu() {
        guard let snapshot, snapshot.providers.count > 1 else { return }
        let menu = NSMenu()
        for provider in snapshot.providers {
            let item = NSMenuItem(title: provider.displayName,
                                  action: #selector(selectProviderFromMenu(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = provider.id
            item.state = provider.id == snapshot.selectedProviderID ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 8, y: bounds.maxY - headerView.frame.height),
                   in: self)
    }

    @objc private func selectProviderFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onProviderChange?(id)
    }

#if DEBUG
    // MARK: - 快照示意数据（仅 DEBUG）

    /// 快照自证专用（仅 DEBUG）：注入原型同款示意数据，不影响真实运行
    ///
    /// - Parameters:
    ///   - configured: false 时渲染「配置 API Key」态
    ///   - errorMessage: 非空时渲染错误条（同时保留余额/用量数据）
    ///   - legacyLimits: 是否注入遗留计划百分比限额（原型 D 状态）
    ///   - legacyUsage: 是否注入「只有请求数、无金额/token」的用量（遗留计划真实返回形态）
    func injectPreview(configured: Bool = true,
                       errorMessage: String? = nil,
                       legacyLimits: Bool = false,
                       legacyUsage: Bool = false) {
        let provider = BillingMonitor.ProviderDescriptor(id: "ollama",
                                                         displayName: "Ollama",
                                                         symbolName: "cloud",
                                                         credentialHint: "Ollama API Key",
                                                         supportsModelBreakdown: true)
        let now = Date()
        guard configured else {
            update(BillingMonitor.Snapshot(providers: [provider],
                                           selectedProviderID: provider.id,
                                           isConfigured: false,
                                           balance: nil,
                                           usage: nil,
                                           range: .last24Hours,
                                           lastUpdated: now,
                                           isLoading: false,
                                           errorMessage: nil))
            return
        }
        let period = BillingPeriod(start: now.addingTimeInterval(-12 * 86_400),
                                   end: now.addingTimeInterval(18 * 86_400))
        let limits = legacyLimits
            ? [BillingPercentLimit(id: "session", title: "会话", remainingFraction: 0.75,
                                   resetsAt: now.addingTimeInterval(-3_600)),
               BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 0.40,
                                   resetsAt: now.addingTimeInterval(3 * 86_400))]
            : []
        // 遗留计划态（原型 D）没有内含额度，只有已购余额 + 百分比限额
        let included: BillingIncludedBalance? = legacyLimits
            ? nil
            : BillingIncludedBalance(remainingUSD: 72.50, allowanceUSD: 100, period: period)
        let balance = BillingBalance(included: included, purchasedUSD: 25, percentLimits: limits)
        update(BillingMonitor.Snapshot(providers: [provider],
                                       selectedProviderID: provider.id,
                                       isConfigured: true,
                                       balance: balance,
                                       usage: Self.previewUsage(endingAt: now, legacyOnly: legacyUsage),
                                       range: .last24Hours,
                                       lastUpdated: now,
                                       isLoading: false,
                                       errorMessage: errorMessage))
    }

    /// 24 小时示意用量：25 个小时桶（含 3 个非零）+ 2 个模型
    ///
    /// - Parameter legacyOnly: 遗留计划真实返回只有 request_count（无金额 / token / 模型分组）
    private static func previewUsage(endingAt now: Date, legacyOnly: Bool = false) -> BillingUsage {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let end = calendar.date(from: components) ?? now
        let start = end.addingTimeInterval(-24 * 3_600)
        if legacyOnly {
            let counts = [0, 0, 0, 0, 120, 0, 0, 0, 0, 0, 860, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                          0, 2_400, 6_300, 8_200, 3_400]
            let legacyBuckets = counts.enumerated().map { index, count in
                let bucketStart = start.addingTimeInterval(Double(index) * 3_600)
                return BillingBucket(start: bucketStart,
                                     end: bucketStart.addingTimeInterval(3_600),
                                     isPartial: index == counts.count - 1,
                                     metrics: BillingMetrics(requestCount: count))
            }
            return BillingUsage(range: .last24Hours,
                                granularity: .hour,
                                start: start,
                                end: end.addingTimeInterval(3_600),
                                totals: BillingMetrics(requestCount: 26_118),
                                buckets: legacyBuckets,
                                groups: [])
        }
        let amounts: [Double] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.0052,
                                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                 0.0088, 0.0042, 0.0032]
        let buckets = amounts.enumerated().map { index, usd in
            let bucketStart = start.addingTimeInterval(Double(index) * 3_600)
            return BillingBucket(start: bucketStart,
                                 end: bucketStart.addingTimeInterval(3_600),
                                 isPartial: index == amounts.count - 1,
                                 metrics: BillingMetrics(requestCount: usd > 0 ? 1 : 0, usageUSD: usd))
        }
        return BillingUsage(range: .last24Hours,
                            granularity: .hour,
                            start: start,
                            end: end.addingTimeInterval(3_600),
                            totals: BillingMetrics(requestCount: 15,
                                                   usageUSD: 0.01718,
                                                   inputTokens: 106_000,
                                                   cachedInputTokens: 46_000,
                                                   outputTokens: 13_600),
                            buckets: buckets,
                            groups: [BillingGroup(name: "glm-5.3-flash",
                                                  metrics: BillingMetrics(requestCount: 12, usageUSD: 0.0132)),
                                     BillingGroup(name: "gpt-oss:120b",
                                                  metrics: BillingMetrics(requestCount: 3, usageUSD: 0.0040))])
    }
#endif
}
