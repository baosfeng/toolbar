import AppKit
import NetworkMonitorCore

// MARK: - 截图与贴图设置页（工具条自定义卡片）

/// 「截图与贴图」页里的工具条卡片 — 文字提示档、组显隐、组顺序、常驻工具、动作按钮
///
/// 从主文件拆出，守住单文件 15 KiB 门禁。
/// 所有写入都走 SnipToolBarConfigurationResolver.persist：设置页与覆盖层共用同一份
/// 键名与编码，不会出现「设置页写了一个键、截图读的是另一个键」的老毛病。
extension SettingsCapturePane {

    // MARK: - 构建

    /// 往页面追加工具条卡片（在 buildContent 里调用）
    func buildToolBarCard() {
        let labelMode = NSSegmentedControl(labels: SnipToolBarLabelMode.allCases.map(\.title),
                                           trackingMode: .selectOne,
                                           target: self,
                                           action: #selector(toolBarLabelModeChanged))
        labelMode.controlSize = .small
        labelMode.font = SettingsTheme.rowTitleFont
        labelMode.setAccessibilityLabel("工具条文字提示")
        SettingsControlChrome.applyStandardHeight(to: labelMode)
        toolBarLabelControl = labelMode
        let labelRow = SettingsRowView(title: "文字提示",
                                      subtitle: toolBarLabelSubtitle())
        labelRow.trailingStack.addArrangedSubview(labelMode)
        toolBarLabelRow = labelRow

        let placement = NSPopUpButton(frame: .zero, pullsDown: false)
        placement.controlSize = .small
        placement.target = self
        placement.action = #selector(toolBarPlacementChanged)
        placement.setAccessibilityLabel("工具条位置")
        placement.font = SettingsTheme.rowTitleFont
        placement.addItems(withTitles: SnipToolBarPlacement.allCases.map(\.title))
        placement.widthAnchor.constraint(equalToConstant: 110).isActive = true
        SettingsControlChrome.applyStandardHeight(to: placement)
        toolBarPlacementControl = placement
        let placementRow = SettingsRowView(title: "位置",
                                           subtitle: "工具条相对选区的位置")
        placementRow.trailingStack.addArrangedSubview(placement)
        toolBarPlacementRow = placementRow

        let card = SettingsCardView()
        card.addRow(labelRow)
        card.addRow(placementRow)

        // 组显隐：四个开关，关掉最后一组会被拦回（否则整条工具条会空）
        for group in SnipToolBarGroup.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(toolBarGroupToggled(_:))
            toggle.tag = SnipToolBarGroup.allCases.firstIndex(of: group) ?? 0
            toggle.setAccessibilityLabel("工具条显示：\(group.displayName)")
            toolBarGroupToggles[group] = toggle
            let row = SettingsRowView(title: group.displayName, subtitle: group.detailText)
            row.trailingStack.addArrangedSubview(toggle)
            card.addRow(row)
        }

        page.addCard(card, sectionTitle: "工具条显示")

        // 排列顺序：交给通用可排序卡片（行尾上移 / 下移 + 标题行「恢复默认」）
        let ordered = SettingsOrderedCardView(orderKey: SnipToolBarPreferenceKey.groupOrder,
                                              defaultOrder: SnipToolBarGroup.allCases.map(\.rawValue),
                                              storage: storage,
                                              onChange: { [weak self] _ in self?.refreshToolBar() })
        for group in SnipToolBarGroup.allCases {
            let row = SettingsRowView(title: group.displayName, subtitle: "工具条上的位置")
            ordered.addRow(id: group.rawValue,
                           row: row,
                           accessibilityPrefix: group.displayName) { [weak row] position in
                row?.update(subtitle: "工具条上第 \(position) 组")
            }
        }
        ordered.finish()
        toolBarOrderCard = ordered
        page.addCard(ordered.card, sectionTitle: "排列顺序", trailingAccessory: ordered.resetButton)

        // 常驻工具：10 个 chip 分两行，点一下切换；未选的收进「更多」面板
        let toolsCard = SettingsCardView()
        let chipsRow = NSStackView()
        chipsRow.orientation = .vertical
        chipsRow.alignment = .leading
        chipsRow.spacing = 6
        for line in toolChipLines() {
            let lineStack = NSStackView()
            lineStack.orientation = .horizontal
            lineStack.alignment = .centerY
            lineStack.spacing = 6
            for tool in line {
                let chip = NSButton(title: tool.displayName, target: self,
                                    action: #selector(toolBarPrimaryToolToggled(_:)))
                chip.setButtonType(.pushOnPushOff)
                chip.bezelStyle = .inline
                chip.controlSize = .small
                chip.tag = SnipTool.allCases.firstIndex(of: tool) ?? 0
                chip.font = SettingsTheme.rowTitleFont
                chip.setAccessibilityLabel("常驻工具：\(tool.displayName)")
                SettingsControlChrome.applyStandardHeight(to: chip)
                toolBarToolChips[tool] = chip
                lineStack.addArrangedSubview(chip)
            }
            chipsRow.addArrangedSubview(lineStack)
        }
        let chipNote = MenuPanelLabel.text("未选的工具收进「更多」面板；至少保留 1 个",
                                          font: SettingsTheme.rowSubtitleFont,
                                          color: SettingsTheme.textSecondary)
        chipsRow.addArrangedSubview(chipNote)
        let toolsRow = SettingsRowView(title: "常驻工具")
        toolsRow.trailingStack.addArrangedSubview(chipsRow)
        toolsCard.addRow(toolsRow)
        page.addCard(toolsCard, sectionTitle: "常驻工具")

        // 输出动作：取消 / 复制 / 保存 / 贴图 —— 一行 = 显示开关 + 行尾上移 / 下移
        // 顺序单独存 snip.toolbar.actionOrder（与显隐解耦），写偏好即下次截图生效
        let actionCard = SettingsOrderedActionCard(
            storage: storage,
            currentConfig: { [weak self] in self?.currentToolBarConfiguration() ?? .standard },
            applyConfig: { [weak self] config in self?.applyToolBarConfiguration(config) })
        actionCard.build()
        toolBarActionCard = actionCard
        page.addCard(actionCard.card, sectionTitle: "输出动作",
                     trailingAccessory: actionCard.resetButton)

        page.addNote("工具条配置立即生效：之后每次截图按新排列与文字提示档上屏。")
        // 构建完立刻按偏好灌一次：设置页首次打开就必须显示真实勾选态，
        // 不能等切页触发的 refresh（离屏快照与首次进页都会绕过它）
        refreshToolBar()
    }

    // MARK: - 刷新

    /// 把偏好灌回控件（refresh 里调用）
    func refreshToolBar() {
        let config = currentToolBarConfiguration()
        toolBarLabelControl?.selectedSegment =
            SnipToolBarLabelMode.allCases.firstIndex(of: config.labelMode) ?? 1
        toolBarLabelRow?.update(subtitle: toolBarLabelSubtitle())
        if let index = SnipToolBarPlacement.allCases.firstIndex(of: config.placement) {
            toolBarPlacementControl?.selectItem(at: index)
        }
        toolBarPlacementRow?.update(subtitle: config.placement.detailText)
        for (group, toggle) in toolBarGroupToggles {
            toggle.state = config.isVisible(group) ? .on : .off
        }
        for (tool, chip) in toolBarToolChips {
            chip.state = config.primaryTools.contains(tool) ? .on : .off
        }
        toolBarActionCard?.refresh(visible: config.visibleActions)
    }

    /// 当前偏好解析出的配置（设置页与覆盖层同一份解析）
    func currentToolBarConfiguration() -> SnipToolBarConfiguration {
        SnipToolBarConfigurationResolver.load(storage: storage)
    }

    /// 写回一份配置（统一过 normalized，非法值不会落到偏好里）
    func applyToolBarConfiguration(_ config: SnipToolBarConfiguration) {
        SnipToolBarConfigurationResolver.persist(config, storage: storage)
        refreshToolBar()
        logger.info("截图工具条配置已更新：显示组 \(config.visibleGroups.count) / 常驻工具 \(config.primaryTools.count)")
    }

    // MARK: - 动作

    @objc func toolBarLabelModeChanged() {
        let index = toolBarLabelControl?.selectedSegment ?? 1
        guard SnipToolBarLabelMode.allCases.indices.contains(index) else { return }
        var config = currentToolBarConfiguration()
        config.labelMode = SnipToolBarLabelMode.allCases[index]
        applyToolBarConfiguration(config)
    }

    @objc func toolBarPlacementChanged() {
        let index = toolBarPlacementControl?.indexOfSelectedItem ?? 0
        guard SnipToolBarPlacement.allCases.indices.contains(index) else { return }
        var config = currentToolBarConfiguration()
        config.placement = SnipToolBarPlacement.allCases[index]
        applyToolBarConfiguration(config)
    }

    @objc func toolBarGroupToggled(_ sender: NSSwitch) {
        guard SnipToolBarGroup.allCases.indices.contains(sender.tag) else { return }
        let group = SnipToolBarGroup.allCases[sender.tag]
        var config = currentToolBarConfiguration()
        var nextGroups = config.visibleGroups
        if sender.state == .on {
            nextGroups.insert(group)
        } else {
            nextGroups.remove(group)
        }
        // 至少保留一组：关到最后一组时拒绝，并把界面勾选态拉回真实值
        guard !nextGroups.isEmpty else {
            sender.state = .on
            return
        }
        config.visibleGroups = nextGroups
        applyToolBarConfiguration(config)
    }

    @objc func toolBarPrimaryToolToggled(_ sender: NSButton) {
        guard SnipTool.allCases.indices.contains(sender.tag) else { return }
        let tool = SnipTool.allCases[sender.tag]
        var config = currentToolBarConfiguration()
        var tools = config.primaryTools
        if tools.contains(tool) {
            // 至少保留一个常驻工具，否则除「更多」以外没有任何画标注的入口
            guard tools.count > 1 else { sender.state = .on; return }
            tools.removeAll { $0 == tool }
        } else {
            tools.append(tool)
        }
        config.primaryTools = tools
        applyToolBarConfiguration(config)
    }

    #if DEBUG
    /// 仅 DEBUG：把工具条卡片的控件勾选态与偏好真值落盘，用于核对「界面显示 vs 实际配置」
    /// （离屏快照里 NSSwitch 的 on/off 只能靠这份文本确认，肉眼看不出状态是否灌对了）
    func debugLogToolBarControlStates(_ tag: String) {
        let config = currentToolBarConfiguration()
        let groupStates = SnipToolBarGroup.allCases.map { group in
            let state = toolBarGroupToggles[group]?.state == .on ? "on" : "off"
            return "\(group.rawValue)=\(config.isVisible(group))/\(state)"
        }.joined(separator: " ")
        let actionStates = SnipBarAction.allCases.map { action in
            let state = toolBarActionCard?.toggles[action]?.state == .on ? "on" : "off"
            return "\(action.rawValue)=\(config.visibleActions.contains(action))/\(state)"
        }.joined(separator: " ")
        let toolStates = SnipTool.allCases.map { tool in
            let state = toolBarToolChips[tool]?.state == .on ? "on" : "off"
            return "\(tool.rawValue)=\(config.primaryTools.contains(tool))/\(state)"
        }.joined(separator: " ")
        let line = "[\(tag)] mode=\(config.labelMode.rawValue) groups: \(groupStates) "
            + "actions: \(actionStates) tools: \(toolStates)"
        SnapshotEvidenceLine.write(line, tag: tag, fileName: "settings-toolbar-states.txt")
    }
    #endif

    // MARK: - 工具

    /// 文字提示档副标题（写出实际效果，避免「选了却看不出变化」）
    private func toolBarLabelSubtitle() -> String {
        currentToolBarConfiguration().labelMode.detailText
    }

    /// 常驻工具 chip 的两行分法（每行 5 个，10 个工具正好两行）
    private func toolChipLines() -> [[SnipTool]] {
        let tools = SnipTool.allCases
        let perLine = 5
        return stride(from: 0, to: tools.count, by: perLine).map { start in
            Array(tools[start..<min(start + perLine, tools.count)])
        }
    }
}
