import AppKit
import NetworkMonitorCore

// MARK: - 额度 Provider 设置页

/// 额度 Provider 设置页 — **按 provider 类型分组**，每个类型一张卡，卡内是该类型的实例行
///
/// 数据来源只有两份：`BillingMonitor`（实例 / 运行状态 / 最近刷新 / 错误文案）与
/// `BillingProviderPreferences`（实例启用开关）。凭据读写沿用 `BillingMonitor` 的
/// `saveCredential` / `clearCredential`，页内不直接碰存储，避免两套写入路径。
///
/// 交互与原型一致：
/// - 每个实例一行；已配置显示「替换 / 清除」，未配置显示「配置凭据…」；右侧统一是启用开关
/// - **同一实例只有一份配置**：已配置时不再提供「配置凭据…」入口，只能「替换」（覆盖唯一那条）或「清除」
/// - 命名实例额外提供「重命名 / 删除」（默认实例没有：删掉它等于让旧配置失去落点）
/// - 每个类型卡底有「＋ 新增实例」：同一 provider 可以配多份凭据（工作号 / 个人号）
/// - 页内每秒重算「上次查询 / 下次刷新倒计时」，异步查询结果无需手动刷新
///
/// 与额度页的关系：本页**展示全部已启用实例**（含未配置的，用户必须有配置入口），
/// 额度页只展示已配置的（判据在 Core 的 `BillingVisibilityRule`）。
///
/// 三类额度通知的「推送 / 声音 / 提醒方式 / 触觉」也放在本页（`notificationCard`）：
/// 业务开关（是否产生提醒）与推送形式在同一页，用户配额度时一次调完。
final class SettingsProvidersPane: SettingsPaneView, SettingsNotificationEventHosting {

    // MARK: - 依赖

    // 以下成员放宽为 internal：`SettingsProvidersPane+Instances` 扩展要做实例增删改
    let monitor: BillingMonitor
    let preferences: BillingProviderPreferences
    /// 恢复提醒偏好（窗口重置 / 余额回升 / 回升阈值）
    let alertPreferences: BillingAlertPreferences
    /// 三类额度通知的推送形式（放宽为 internal：DEBUG 快照要按协议取到它）
    let notificationCard: SettingsNotificationEventCard

    // MARK: - 子视图

    /// 每 provider 类型一张卡（键 = kindID）
    private var kindCards: [String: SettingsCardView] = [:]
    /// 类型出现顺序（注册表顺序；「新增实例」按钮用 tag 传有界索引）
    var kindOrder: [String] = []
    /// 实例行（键 = 实例标识）
    var rows: [String: ProviderRowView] = [:]
    private var countdownTimer: Timer?

    let toastView = NSView()
    let toastLabel = MenuPanelLabel.text("", font: NSFont.systemFont(ofSize: 11.5),
                                                 color: .white)
    private var toastTask: Task<Void, Never>?

    // MARK: - 初始化

    init(monitor: BillingMonitor,
         preferences: BillingProviderPreferences = BillingProviderPreferences(),
         alertPreferences: BillingAlertPreferences? = nil,
         notificationContext: SettingsNotificationEventContext) {
        self.monitor = monitor
        self.preferences = preferences
        self.alertPreferences = alertPreferences ?? BillingAlertPreferences()
        self.notificationCard = SettingsNotificationEventCard(
            events: [.billingAlert, .billingWindowReset, .billingRecovery],
            context: notificationContext)
        super.init(section: .providers)
    }

    // MARK: - 构建

    override func buildContent() {
        let registrations = monitor.registry.registrations
        if registrations.isEmpty {
            page.addNote("暂无已注册的额度 Provider。")
        } else {
            buildProviderCards(registrations)
            buildAlertCard()
        }
        buildNotificationCard()
        buildToast()
        page.addNote("同一 provider 可配多个实例（如工作号 / 个人号），每个实例一份 Key。"
                     + "默认实例的键与旧版本一致；关闭开关不会删除凭据，未配置的实例不会出现在额度页。")
    }

    /// 额度通知 — 三类事件的推送形式（业务开关在上一张卡，两处各管一层）
    private func buildNotificationCard() {
        page.addCard(notificationCard.card, sectionTitle: "额度通知")
        page.addNote("系统通知的横幅样式由 macOS 决定：位置、停留时长与是否出横幅都在系统设置「通知」里，"
                     + "应用只能决定「有没有声音」「要不要横幅」「要不要进通知中心」。"
                     + "「额度偏低提醒」总开关在「通用」页。")
    }

    private func buildProviderCards(_ registrations: [BillingRegistration]) {
        kindOrder = []
        for registration in registrations where !kindOrder.contains(registration.instance.kindID) {
            kindOrder.append(registration.instance.kindID)
        }
        for kindID in kindOrder {
            let card = SettingsCardView()
            kindCards[kindID] = card
            page.addCard(card, sectionTitle: kindTitle(kindID))
            rebuildKindCard(kindID)
        }
    }

    /// 类型展示名：优先默认实例的标题（就是 provider 展示名），否则用注册表里第一个实例
    func kindTitle(_ kindID: String) -> String {
        monitor.registry.instance(id: kindID)?.title
            ?? monitor.registry.registrations(ofKind: kindID).first?.instance.title
            ?? kindID
    }

    /// 重建某个类型的卡片（实例增删 / 重命名后调用）
    func rebuildKindCard(_ kindID: String) {
        guard let card = kindCards[kindID] else { return }
        card.removeAllRows()
        for registration in monitor.registry.registrations(ofKind: kindID) {
            rows[registration.instance.id] = nil
            card.addRow(makeRow(registration))
        }
        card.addRow(makeAddInstanceRow(kindID: kindID))
        refresh()
    }

    private func makeRow(_ registration: BillingRegistration) -> ProviderRowView {
        let instance = registration.instance
        let row = ProviderRowView(provider: registration.provider, instance: instance)
        row.onToggle = { [weak self] enabled in
            self?.monitor.setProviderEnabled(enabled, providerID: instance.id)
            self?.refresh()
        }
        row.onSave = { [weak self] key in self?.save(key, instanceID: instance.id) }
        row.onClearConfirmed = { [weak self] in self?.clear(instanceID: instance.id) }
        row.onRename = { [weak self] in self?.promptRename(instance) }
        row.onDeleteInstance = { [weak self] in self?.confirmDeleteInstance(instance) }
        row.onEditingChanged = { [weak self] editing in
            self?.setRowsLocked(except: instance.id, locked: editing)
        }
        rows[instance.id] = row
        return row
    }

    /// 「＋ 新增实例」行（tag 在 `kindOrder` 的有界区间内，不与其他模块共享 tag 空间）
    private func makeAddInstanceRow(kindID: String) -> SettingsRowView {
        let row = SettingsRowView(title: "新增实例",
                                  subtitle: "同一 provider 可配多份凭据（如工作号 / 个人号）")
        let button = ProviderRowView.textButton("＋ 新增实例")
        button.target = self
        button.action = #selector(addInstanceTapped(_:))
        button.tag = kindOrder.firstIndex(of: kindID) ?? 0
        button.setAccessibilityLabel("新增 \(kindTitle(kindID)) 实例")
        row.trailingStack.addArrangedSubview(button)
        return row
    }

    // MARK: - 刷新

    /// 每秒与切页时同步：状态点、错误文案、刷新倒计时都从 monitor 的实时状态重算
    ///
    /// 已配置与否、掩码、来源都取自 `credentialResolution`（Core 的唯一凭据入口）：
    /// 同一实例只有一条生效凭据，本页显示的就是额度页实际查询用的那条。
    override func refresh() {
        let now = Date()
        var states: [String: BillingMonitor.ProviderState] = [:]
        for state in monitor.states { states[state.descriptor.id] = state }
        for registration in monitor.registry.registrations {
            let instanceID = registration.instance.id
            guard let row = rows[instanceID] else { continue }
            let resolution = monitor.credentialStore.credentialResolution(for: instanceID)
            row.update(isEnabled: preferences.isEnabled(instanceID),
                       isConfigured: resolution.isConfigured,
                       credentialMask: resolution.credential.map(Self.mask),
                       credentialSource: resolution.source,
                       interval: BillingRefreshScheduler.interval(
                           providerMinimum: registration.provider.minimumRefreshInterval),
                       state: states[instanceID],
                       lastAttempt: monitor.lastAttempts[instanceID],
                       now: now)
        }
        notificationCard.refresh()
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
    private func save(_ key: String, instanceID: String) {
        guard let row = rows[instanceID] else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = monitor.credentialStore.credentialResolution(for: instanceID)
        guard let credential = trimmed.isEmpty ? existing.credential : trimmed else {
            row.showEditorMessage("请先填写 Key，再保存并查询。")
            return
        }
        row.endEditing()
        // 停用中的实例：先落盘（saveCredential 对无 state 的实例只写存储），
        // 再启用重建状态并查询，避免用旧凭据多打一次请求
        monitor.saveCredential(credential, providerID: instanceID)
        if !preferences.isEnabled(instanceID) {
            monitor.setProviderEnabled(true, providerID: instanceID)
        }
        refresh()
        // 空输入 = 沿用唯一那条已有凭据（同一实例不会因此多出第二份配置）
        showToast(trimmed.isEmpty ? "已沿用原凭据并重新查询" : "已保存并查询")
    }

    /// 清除凭据（开关保持原状：该实例随即从额度页消失，本页仍保留配置入口）
    private func clear(instanceID: String) {
        guard let row = rows[instanceID] else { return }
        row.endConfirm()
        monitor.clearCredential(providerID: instanceID)
        refresh()
        showToast("已清除凭据")
    }

    /// 编辑 / 确认展开时禁用其他行，避免两行同时编辑
    private func setRowsLocked(except instanceID: String, locked: Bool) {
        for (id, row) in rows where id != instanceID {
            row.setInteractionEnabled(!locked)
        }
    }

    // MARK: - 文案

    /// 凭据掩码（保留前 3 后 4，短值全掩）
    static func mask(_ credential: String) -> String {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return "••••" }
        return "\(trimmed.prefix(3))…\(trimmed.suffix(4))"
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

    func showToast(_ text: String) {
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
