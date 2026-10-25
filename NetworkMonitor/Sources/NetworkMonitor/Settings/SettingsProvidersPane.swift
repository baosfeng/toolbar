import AppKit
import NetworkMonitorCore

// MARK: - 额度 Provider 设置页

/// 额度 Provider 设置页 — 启用开关、行内凭据编辑、状态与刷新节奏
///
/// 数据来源只有两份：`BillingMonitor`（运行状态 / 最近刷新 / 错误文案）与
/// `BillingProviderPreferences`（启用开关）。凭据读写沿用 `BillingMonitor` 的
/// `saveCredential` / `clearCredential`，页内不直接碰存储，避免两套写入路径。
///
/// 交互与原型一致：
/// - 配置态显示「替换 / 清除」，未配置显示「配置凭据…」；右侧统一是启用开关
/// - 行内编辑区展开时显示 Key 输入（已配置时占位文案带掩码）与「保存并查询 / 取消」
/// - 清除走行内二次确认；编辑或确认展开时其余行降透明度并禁用，避免并发编辑
/// - 页内每秒重算「上次查询 / 下次刷新倒计时」，异步查询结果无需手动刷新
final class SettingsProvidersPane: SettingsPaneView {

    // MARK: - 依赖

    private let monitor: BillingMonitor
    private let preferences: BillingProviderPreferences

    // MARK: - 子视图

    private let providerCard = SettingsCardView()
    private let cadenceCard = SettingsCardView()
    private var rows: [String: ProviderRowView] = [:]
    private var countdownTimer: Timer?

    private let toastView = NSView()
    private let toastLabel = MenuPanelLabel.text("", font: NSFont.systemFont(ofSize: 11.5),
                                                 color: .white)
    private var toastTask: Task<Void, Never>?

    // MARK: - 初始化

    init(monitor: BillingMonitor,
         preferences: BillingProviderPreferences = BillingProviderPreferences()) {
        self.monitor = monitor
        self.preferences = preferences
        super.init(section: .providers)
    }

    // MARK: - 构建

    override func buildContent() {
        let providers = monitor.registry.all
        guard !providers.isEmpty else {
            page.addNote("暂无已注册的额度 Provider。")
            return
        }

        for provider in providers {
            let row = ProviderRowView(provider: provider)
            row.onToggle = { [weak self] enabled in
                self?.monitor.setProviderEnabled(enabled, providerID: provider.id)
                self?.refresh()
            }
            row.onSave = { [weak self] key in self?.save(key, providerID: provider.id) }
            row.onClearConfirmed = { [weak self] in self?.clear(providerID: provider.id) }
            row.onEditingChanged = { [weak self] editing in
                self?.setRowsLocked(except: provider.id, locked: editing)
            }
            providerCard.addRow(row)
            rows[provider.id] = row
        }
        page.addCard(providerCard, sectionTitle: "Provider")

        for provider in providers {
            let interval = BillingRefreshScheduler.interval(providerMinimum: provider.minimumRefreshInterval)
            let row = SettingsRowView(title: provider.displayName)
            row.trailingStack.addArrangedSubview(valueLabel(Self.intervalText(interval)))
            cadenceCard.addRow(row)
        }
        page.addCard(cadenceCard, sectionTitle: "刷新节奏（只读）")

        page.addNote("Key 仅保存在本机偏好设置中，关闭开关不会删除凭据，可随时再打开。")
        buildToast()
    }

    // MARK: - 刷新

    /// 每秒与切页时同步：状态点、错误文案、刷新倒计时都从 monitor 的实时状态重算
    override func refresh() {
        let now = Date()
        var states: [String: BillingMonitor.ProviderState] = [:]
        for state in monitor.states { states[state.descriptor.id] = state }
        for provider in monitor.registry.all {
            guard let row = rows[provider.id] else { continue }
            let credential = monitor.credentialStore.credential(for: provider.id)
            row.update(isEnabled: preferences.isEnabled(provider.id),
                       isConfigured: credential != nil,
                       credentialMask: credential.map(Self.mask),
                       interval: BillingRefreshScheduler.interval(
                           providerMinimum: provider.minimumRefreshInterval),
                       state: states[provider.id],
                       lastAttempt: monitor.lastAttempts[provider.id],
                       now: now)
        }
    }

    // MARK: - 生命周期（倒计时）

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            countdownTimer?.invalidate()
            countdownTimer = nil
        } else if countdownTimer == nil {
            // selector 形式而非 block：block 是 @Sendable，Swift 6 下不能捕获 NSView
            let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick),
                              userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            countdownTimer = timer
        }
    }

    @objc private func tick() {
        refresh()
    }

    // MARK: - 动作

    /// 保存并查询：输入为空时沿用已有凭据（「替换」未填写等于重新查询）
    private func save(_ key: String, providerID: String) {
        guard let row = rows[providerID] else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = monitor.credentialStore.credential(for: providerID)
        guard let credential = trimmed.isEmpty ? existing : trimmed else {
            row.showEditorMessage("请先填写 Key，再保存并查询。")
            return
        }
        row.endEditing()
        // 停用中的 provider：先落盘（saveCredential 对无 state 的 provider 只写存储），
        // 再启用重建状态并查询，避免用旧凭据多打一次请求
        monitor.saveCredential(credential, providerID: providerID)
        if !preferences.isEnabled(providerID) {
            monitor.setProviderEnabled(true, providerID: providerID)
        }
        refresh()
        showToast("已保存并查询")
    }

    /// 清除凭据（开关保持原状：启用但未配置的 provider 继续留在额度页，点「去设置配置」）
    private func clear(providerID: String) {
        guard let row = rows[providerID] else { return }
        row.endConfirm()
        monitor.clearCredential(providerID: providerID)
        refresh()
        showToast("已清除凭据")
    }

    /// 编辑 / 确认展开时禁用其他行，避免两行同时编辑
    private func setRowsLocked(except providerID: String, locked: Bool) {
        for (id, row) in rows where id != providerID {
            row.setInteractionEnabled(!locked)
        }
    }

    // MARK: - 文案

    /// 刷新间隔文案（60 秒 / 5 分钟）
    static func intervalText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 120 { return "\(seconds) 秒" }
        if seconds % 60 == 0 { return "\(seconds / 60) 分钟" }
        return "\(seconds) 秒"
    }

    /// 凭据掩码（保留前 3 后 4，短值全掩）
    static func mask(_ credential: String) -> String {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "••••" }
        return "\(trimmed.prefix(3))…\(trimmed.suffix(4))"
    }

    private func valueLabel(_ text: String) -> NSTextField {
        let label = MenuPanelLabel.text(text, font: SettingsStyle.rowValueFont,
                                        color: .secondaryLabelColor)
        label.alignment = .right
        return label
    }

    // MARK: - toast

    private func buildToast() {
        toastView.translatesAutoresizingMaskIntoConstraints = false
        toastView.wantsLayer = true
        toastView.layer?.cornerRadius = 12
        toastView.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.94).cgColor
        toastView.isHidden = true
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastView.addSubview(toastLabel)
        addSubview(toastView)
        NSLayoutConstraint.activate([
            toastLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 12),
            toastLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -12),
            toastLabel.topAnchor.constraint(equalTo: toastView.topAnchor, constant: 6),
            toastLabel.bottomAnchor.constraint(equalTo: toastView.bottomAnchor, constant: -6),
            toastView.centerXAnchor.constraint(equalTo: centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    private func showToast(_ text: String) {
        toastLabel.stringValue = text
        toastView.isHidden = false
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.toastView.isHidden = true
        }
    }
}
