import AppKit
import NetworkMonitorCore

// MARK: - 额度 Provider 设置页（恢复提醒卡）

/// 恢复提醒卡 —— 从「实例增删改」扩展拆出（同族行数门禁：只降不升）
///
/// 卡内三块：
/// 1. 金额恢复通知总开关（是否产生恢复类提醒）；
/// 2. **按窗口勾选**（每个已配置实例一行，只列该 provider 实际出现过 / 声明的窗口种类）；
/// 3. 额度回升通知与回升阈值。
///
/// 窗口勾选只作用于「恢复通知」：用尽与回升不受影响，勾选决定哪一类窗口重置时值得说一声
/// （用户口径「可以自定义恢复通知，比如打开周额度还是小时额度」）。
extension SettingsProvidersPane {

    /// 按当前实例与凭据态重建卡内全部行
    ///
    /// 窗口行的集合随「已配置实例」与「实际观测到的窗口」变化：实例增删、保存或清除凭据、
    /// 首次拿到余额都可能改变清单，因此这里整卡重建；调用方用指纹判断是否需要重建。
    func rebuildAlertCardRows() {
        alertCard.removeAllRows()
        windowChecks = [:]

        let recoveredRow = SettingsRowView(title: "额度恢复通知",
                                           subtitle: "仅在额度用尽后重新可用时提醒")
        recoveredSwitch.state = alertPreferences.isRecoveredNotificationEnabled ? .on : .off
        recoveredSwitch.target = self
        recoveredSwitch.action = #selector(toggleRecoveredNotification(_:))
        recoveredSwitch.setAccessibilityLabel("额度恢复通知开关")
        recoveredRow.trailingStack.addArrangedSubview(recoveredSwitch)
        alertCard.addRow(recoveredRow)

        // 只有配了凭据的实例才可能有恢复通知，未配置的不占位（与额度页可见性口径一致）
        for registration in monitor.registry.registrations
        where monitor.credentialStore.credentialResolution(for: registration.instance.id).isConfigured {
            alertCard.addRow(makeRecoveredWindowRow(registration))
        }

        let recoveryRow = SettingsRowView(title: "额度回升通知",
                                          subtitle: "剩余额度回升达到阈值时提醒")
        recoverySwitch.state = alertPreferences.isRecoveryNotificationEnabled ? .on : .off
        recoverySwitch.target = self
        recoverySwitch.action = #selector(toggleRecoveryNotification(_:))
        recoverySwitch.setAccessibilityLabel("额度回升通知开关")
        recoveryRow.trailingStack.addArrangedSubview(recoverySwitch)
        alertCard.addRow(recoveryRow)

        let thresholdRow = SettingsRowView(title: "回升阈值",
                                           subtitle: "百分点（1–50），默认 10")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = SettingsTheme.rowValueFont
        SettingsControlChrome.applyStandardHeight(to: popup)
        for percent in Self.recoveryThresholdChoices(including: alertPreferences.recoveryMinimumPercent) {
            popup.addItem(withTitle: "\(Int(percent)) 个百分点")
            popup.lastItem?.representedObject = percent
            if percent == alertPreferences.recoveryMinimumPercent {
                popup.selectItem(at: popup.numberOfItems - 1)
            }
        }
        popup.target = self
        popup.action = #selector(changeRecoveryMinimum(_:))
        popup.setAccessibilityLabel("额度回升阈值")
        thresholdRow.trailingStack.addArrangedSubview(popup)
        alertCard.addRow(thresholdRow)
        refreshWindowCheckStates()
    }

    /// 单个实例的窗口勾选行（一行装下 1–4 个窗口）
    private func makeRecoveredWindowRow(_ registration: BillingRegistration) -> SettingsRowView {
        let instance = registration.instance
        let kinds = BillingWindowKindInventory.options(
            balance: balance(for: instance.id),
            declared: registration.provider.declaredQuotaWindowKinds)
        let row = SettingsRowView(
            title: "\(instance.title) 恢复通知窗口",
            subtitle: kinds.count > 1 ? "只通知勾选的窗口；未勾选的窗口恢复时静默" : "该额度只有一个窗口")
        var checks: [BillingWindowKind: NSButton] = [:]
        for kind in kinds {
            let box = NSButton(checkboxWithTitle: kind.title, target: self,
                               action: #selector(recoveredWindowToggled(_:)))
            box.controlSize = .small
            box.font = SettingsTheme.rowTitleFont
            // tag 只在本卡的多选按钮之间共享（BillingWindowKind.allCases 的有界序号，不跨模块）
            box.tag = BillingWindowKind.allCases.firstIndex(of: kind) ?? 0
            box.identifier = NSUserInterfaceItemIdentifier(instance.id)
            box.setAccessibilityLabel("\(instance.title) \(kind.title)窗口恢复通知")
            row.trailingStack.addArrangedSubview(box)
            checks[kind] = box
        }
        windowChecks[instance.id] = checks
        return row
    }

    /// 当前实例最近一次成功查询的余额（窗口种类只从真实数据里取）
    func balance(for instanceID: String) -> BillingBalance? {
        monitor.states.first { $0.descriptor.id == instanceID }?.balance
    }

    /// 把偏好真值灌回勾选框（勾选态与偏好必须一致，见踩坑「离屏快照看不出开关状态」）
    func refreshWindowCheckStates() {
        for (instanceID, checks) in windowChecks {
            for (kind, box) in checks {
                box.state = alertPreferences.isRecoveredWindowEnabled(providerID: instanceID,
                                                                     windowKind: kind) ? .on : .off
            }
        }
    }

    /// 恢复提醒卡的指纹 —— 已配置实例 + 各自观测到的窗口种类
    ///
    /// 只在指纹变化时重建整卡：每秒 tick 都走 refresh，重建会打断正在操作的下拉与勾选。
    func alertCardFingerprint() -> [String] {
        monitor.registry.registrations.compactMap { registration in
            let id = registration.instance.id
            guard monitor.credentialStore.credentialResolution(for: id).isConfigured else { return nil }
            let kinds = BillingWindowKindInventory.options(
                balance: balance(for: id),
                declared: registration.provider.declaredQuotaWindowKinds)
            return id + ":" + kinds.map(\.rawValue).joined(separator: ",")
        }
    }

    /// 阈值候选（含用户当前值；保持升序）
    static func recoveryThresholdChoices(including current: Double) -> [Double] {
        var values: [Double] = [5, 10, 15, 20, 30]
        if !values.contains(current) { values.append(current) }
        return values.sorted()
    }

    // MARK: - 动作

    @objc func recoveredWindowToggled(_ sender: NSButton) {
        let kinds = BillingWindowKind.allCases
        guard kinds.indices.contains(sender.tag),
              let instanceID = sender.identifier?.rawValue else { return }
        let kind = kinds[sender.tag]
        alertPreferences.setRecoveredWindowEnabled(sender.state == .on,
                                                   providerID: instanceID,
                                                   windowKind: kind)
        showToast("\(kind.title)窗口恢复提醒已\(sender.state == .on ? "开启" : "关闭")")
    }

    @objc func toggleRecoveredNotification(_ sender: NSSwitch) {
        alertPreferences.setRecoveredNotificationEnabled(sender.state == .on)
        showToast(sender.state == .on ? "额度恢复提醒已开启" : "额度恢复提醒已关闭")
    }

    @objc func toggleRecoveryNotification(_ sender: NSSwitch) {
        alertPreferences.setRecoveryNotificationEnabled(sender.state == .on)
        showToast(sender.state == .on ? "额度回升提醒已开启" : "额度回升提醒已关闭")
    }

    @objc func changeRecoveryMinimum(_ sender: NSPopUpButton) {
        guard let percent = sender.selectedItem?.representedObject as? Double else { return }
        alertPreferences.setRecoveryMinimumPercent(percent)
        showToast("回升阈值已设为 \(Int(alertPreferences.recoveryMinimumPercent)) 个百分点")
    }
}