import AppKit
import NetworkMonitorCore

// MARK: - 额度页

/// 额度页 — 页头（provider / 刷新）、余额卡、用量区、凭据配置态、错误条与空态
///
/// 数据由 `BillingMonitor` 通过 `update(_:)` 注入；本视图不直接访问网络或凭据存储。
/// 键盘可达行顺序：provider 切换（多 provider 时）→ 刷新 → 范围按钮 → 重试 / 保存 → 官网链接。
/// 快照示意数据构造见 `BillingPanePreview.swift`（仅 DEBUG）。
final class BillingPaneView: MenuPanelPaneView {

    // MARK: - 回调

    /// 点「刷新」（force 刷新）
    var onRefresh: (() -> Void)?
    /// 点错误条「重试」
    var onRetry: (() -> Void)?
    /// 切换用量范围
    var onRangeChange: ((BillingRange) -> Void)?
    /// 「保存并查询」提交凭据
    var onSaveCredential: ((String) -> Void)?
    /// 「前往 provider 网站获取凭据」（参数为快照里当前 provider 的页面地址）
    var onOpenProviderSite: ((URL) -> Void)?
    /// 多 provider 时切换 provider
    var onProviderChange: ((String) -> Void)?

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
        setupView.onOpenSite = { [weak self] in
            guard let url = self?.currentProviderPageURL else { return }
            self?.onOpenProviderSite?(url)
        }

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
        setupView.update(placeholder: snapshot.currentProvider?.credentialHint ?? "凭据",
                         linkText: Self.credentialLinkText(for: snapshot.currentProvider),
                         showsLink: currentProviderPageURL != nil)

        guard snapshot.isConfigured else { return }
        balanceSection.update(balance: snapshot.balance)
        usageSection.update(usage: snapshot.usage,
                            range: snapshot.range,
                            showsModelBreakdown: snapshot.currentProvider?.supportsModelBreakdown ?? false,
                            showsTimeSeries: snapshot.currentProvider?.supportsTimeSeries ?? true)
    }

    // MARK: - provider 文案

    /// 当前 provider 的凭据获取页面（nil = 该 provider 无在线入口，配置态不显示链接行）
    private var currentProviderPageURL: URL? {
        snapshot?.currentProvider?.credentialPageURL
    }

    /// 配置态链接文案 — 有官方 Key 页面的 provider 点明域名，其余用通用文案
    ///
    /// 纯函数便于单测直接断言；域名取自 provider 快照，不为具体 provider 加分支。
    static func credentialLinkText(for provider: BillingMonitor.ProviderDescriptor?) -> String {
        let name = provider?.displayName ?? "provider"
        if name == "Ollama", let host = provider?.credentialPageURL?.host {
            return "在 \(host) 获取 API Key"
        }
        return "前往 \(name) 网站获取凭据"
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
}
