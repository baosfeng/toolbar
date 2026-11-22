import AppKit
import NetworkMonitorCore

// MARK: - Token 用量设置页（数据来源卡）

/// 「数据来源」卡的整块装配与状态刷新 —— 从 `SettingsTokenPane.swift` 与 `+Actions.swift` 拆出。
///
/// 这是一个完整职责：卡内两段（后台自动监控行 / 每源一行）怎么搭、每次刷新怎么按
/// `SettingsTokenController` 的读数填、以及行内动作（启用开关 / 选择目录）与自动监控
/// 偏好的写入。索引规模行、解压工具行属于「索引」卡，重扫与清理属于「维护」卡，
/// 都不在这里；主文件只保留三张卡的调用顺序与索引 / 维护卡本身。
extension SettingsTokenPane {

    // MARK: - 自动监控（卡的配置行）

    /// 间隔可选值（秒）—— 下限 60s：未变更文件只花一次目录枚举 + 一次 SQLite 查询
    static let intervalOptions: [TimeInterval] = [60, 300, 900, 1800]

    static func intervalTitle(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? String(minutes / 60) + " 小时" : String(minutes) + " 分钟"
    }

    // MARK: - 装配

    func buildSourceCard() {
        // 关键约定「首次启用来源会自动打开」必须能被看到：副标题允许折成两行
        autoRow.subtitleAllowsTwoLines()
        autoSwitch.target = self
        autoSwitch.action = #selector(autoIndexToggled)
        autoSwitch.setAccessibilityLabel("后台自动监控开关")
        intervalControl.controlSize = .small
        intervalControl.removeAllItems()
        intervalControl.addItems(withTitles: Self.intervalOptions.map { Self.intervalTitle($0) })
        intervalControl.target = self
        intervalControl.action = #selector(autoIndexIntervalChanged)
        intervalControl.setAccessibilityLabel("自动监控间隔")
        SettingsControlChrome.applyStandardHeight(to: intervalControl)
        autoRow.trailingStack.addArrangedSubview(intervalControl)
        autoRow.trailingStack.addArrangedSubview(autoSwitch)

        let card = SettingsCardView()
        card.addRow(autoRow)
        for source in TokenSourceID.allCases {
            let row = SettingsTokenSourceRowView(source: source)
            row.onToggle = { [weak self] enabled in self?.setSourceEnabled(source, enabled: enabled) }
            row.onChoose = { [weak self] in self?.chooseDirectory(for: source) }
            sourceRows[source] = row
            card.addRow(row)
        }

        zstdValueLabel.lineBreakMode = .byTruncatingMiddle
        zstdValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zstdValueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        zstdRow.trailingStack.addArrangedSubview(zstdDot)
        zstdRow.trailingStack.addArrangedSubview(zstdValueLabel)
        // 解压工具不属于任何来源，放这里会被当成第 8 个来源：挪到「索引」卡顶部（见 buildIndexCard）
        page.addCard(card, sectionTitle: "数据来源")
    }

    /// 数据来源的口径说明（跟在索引 / 维护卡之后，与「来源清单」这件事同源）
    func addSourceNote() {
        page.addNote("数据来自各工具的本地会话日志：DSH（session*.jsonl.zstd）、Claude Code（transcript JSONL）、"
                     + "Codex（rollout JSONL）、Gemini CLI、Copilot CLI、OpenCode、Zed。"
                     + "每个来源可以单独指定目录与开关；关掉的来源不再参与索引与「全部」统计，已有数据保留、"
                     + "重新打开即恢复。面板页头的来源切换器只列「已启用且有数据」的来源。")
    }

    // MARK: - 刷新

    /// 刷新来源清单：每源一行按读数填状态 / 路径 / 规模 / 开关可用性，末了同步自动监控控件
    ///
    /// 跨文件（主文件 refreshSourceCard）调用故为 internal。
    func refreshSourceRows() {
        let readings = controller.sourceReadings()
        self.readings = Dictionary(uniqueKeysWithValues: readings.map { ($0.source, $0) })
        for reading in readings {
            guard let row = sourceRows[reading.source] else { continue }
            row.update(path: reading.path,
                       status: reading.status,
                       counts: reading.countsText,
                       enabled: reading.enabled)
            // 未安装时开关置灰：开着却什么都扫不到是最容易误判成「功能坏了」的状态
            row.setToggleEnabled(reading.status.canEnable)
        }
        syncAutoIndexControls()
    }

    private func syncAutoIndexControls() {
        autoSwitch.state = TokenSourcePreferences.autoIndexEnabled(controller.storage) ? .on : .off
        let interval = TokenSourcePreferences.autoIndexInterval(controller.storage)
        if let index = Self.intervalOptions.firstIndex(where: { $0 == interval }) {
            intervalControl.selectItem(at: index)
        } else {
            // 偏好里的值不在候选里（手改过 plist）：保留显示，不悄悄改成候选值
            intervalControl.selectItem(at: 0)
        }
    }

    // MARK: - 行内动作：来源开关 / 选择目录

    /// 打开 / 关闭某个来源
    ///
    /// 关闭 = 不参与索引与「全部」统计，已有数据保留（切回来即恢复）。
    /// 首次启用任一来源时把后台监控一并打开（缺键即关的默认值 + 「配置完就自己跑起来」的落地点），
    /// 并在卡首行说明，不静默改用户的开关而不交代。
    func setSourceEnabled(_ source: TokenSourceID, enabled: Bool) {
        TokenSourcePreferences.setEnabled(enabled, for: source, storage: controller.storage)
        if enabled, !TokenSourcePreferences.autoIndexEnabled(controller.storage) {
            TokenSourcePreferences.setAutoIndexEnabled(true, storage: controller.storage)
            autoRow.update(title: nil,
                           subtitle: "已自动开启后台自动监控（首次启用来源时默认打开，可随时关闭）")
            logger.info("Token 来源首次启用，已自动打开后台自动监控：" + source.rawValue)
        }
        logger.info("Token 来源" + (enabled ? "启用：" : "停用：") + source.rawValue)
        refresh()
    }

    /// 选择某来源的会话目录：选完先校验是目录，再落偏好（不自动重扫，动作分开）
    func chooseDirectory(for source: TokenSourceID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 " + source.displayName + " 的会话目录"
        panel.prompt = "选择"
        panel.message = "选择存放 " + source.displayName + " 会话记录的目录；改完点「重新扫描」生效"
        let current = readings[source]?.path ?? ""
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current, isDirectory: true) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SettingsTokenController.isValidDirectory(url) else {
            presentAlert(title: "无法使用该目录", message: "选中的位置不是可用的文件夹。", style: .warning)
            return
        }
        TokenSourcePreferences.setRootPath(url.path, for: source, storage: controller.storage)
        refresh()
        logger.info("设置页切换 " + source.rawValue + " 会话目录：" + url.path)
    }

    /// 统一的一次性提示（不叠加窗口：设置页已有足够上下文）
    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 自动监控动作

    @objc func autoIndexToggled() {
        setAutoIndex(enabled: autoSwitch.state == .on)
    }

    /// 写入自动监控开关（缺键即关；打开即按当前间隔走增量）
    func setAutoIndex(enabled: Bool) {
        TokenSourcePreferences.setAutoIndexEnabled(enabled, storage: controller.storage)
        autoRow.update(title: nil,
                       subtitle: enabled
                           ? "按下面间隔增量扫描已启用的来源（未变更文件零成本）"
                           : "已关闭：只在你点「重新扫描」或打开面板时才索引")
        logger.info("Token 后台自动监控" + (enabled ? "已开启" : "已关闭"))
    }

    @objc func autoIndexIntervalChanged() {
        let index = intervalControl.indexOfSelectedItem
        guard Self.intervalOptions.indices.contains(index) else { return }
        let seconds = Self.intervalOptions[index]
        TokenSourcePreferences.setAutoIndexInterval(seconds, storage: controller.storage)
        logger.info("Token 后台自动监控间隔改为 " + String(Int(seconds)) + "s")
    }
}
