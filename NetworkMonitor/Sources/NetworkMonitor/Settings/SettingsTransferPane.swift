import AppKit
import NetworkMonitorCore

// MARK: - 局域网互传设置页

/// 局域网互传设置 — 接收目录、免配对窗口、体积阈值与提示音
///
/// 迁移自 `TransferSettingsWindow`：目录占用与清理走 `TransferService` 既有方法，
/// 倒计时由 `TransferPreferences.windowRemainingText()` 每秒刷新，设置写入同一份偏好。
final class SettingsTransferPane: SettingsPaneView {

    private let preferences: TransferPreferences
    /// 放宽为 internal：接收目录扩展文件（`SettingsTransferPane+ReceiveDirectory`）要用
    let service: TransferService
    /// 放宽为 internal：接收目录扩展文件要写日志
    let logger: LoggingService

    /// 放宽为 internal：接收目录扩展文件要刷新副标题
    let directoryRow = SettingsRowView(title: "接收目录")
    private let autoAcceptSwitch = NSSwitch()
    private let thresholdSwitch = NSSwitch()
    private let thresholdField = NSTextField()
    private let remainingDot = SettingsStatusDotView()
    private let remainingLabel = MenuPanelLabel.text("", font: SettingsStyle.rowValueFont,
                                                      color: .secondaryLabelColor)
    private var durationControl: NSSegmentedControl?
    private var restartButton: NSButton?
    /// 放宽为 internal：接收目录扩展文件要在切换目录时禁用
    var chooseButton: NSButton?
    /// 放宽为 internal：接收目录扩展文件要在清理时禁用
    var clearButton: NSButton?
    private var soundSwitches: [TransferPreferences.SoundEvent: NSSwitch] = [:]
    private var countdownTimer: Timer?
    /// 放宽为 internal：接收目录扩展文件要拼副标题
    var usageText = "统计中…"

    init(preferences: TransferPreferences = TransferPreferences(),
         service: TransferService,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.service = service
        self.logger = logger
        super.init(section: .transfer)
    }

    // MARK: - 构建

    override func buildContent() {
        buildReceiveSection()
        buildAutoAcceptSection()
        buildTransferSection()
        buildSoundSection()
        page.addNote("「选择…」切换接收目录后只影响之后的接收，已接收的文件留在原目录；"
                     + "清理会删除当前目录下全部文件。免配对窗口到期后回到 PIN 确认。")
    }

    private func buildReceiveSection() {
        clearButton = SettingsLinkButton.make("清理", target: self,
                                              action: #selector(clearReceivedFiles),
                                              color: .systemRed)
        chooseButton = SettingsLinkButton.make("选择…", target: self,
                                               action: #selector(chooseReceiveDirectory))
        if let chooseButton { directoryRow.trailingStack.addArrangedSubview(chooseButton) }
        directoryRow.trailingStack.addArrangedSubview(
            SettingsLinkButton.make("打开", target: self, action: #selector(openReceiveDirectory)))
        if let clearButton { directoryRow.trailingStack.addArrangedSubview(clearButton) }
        directoryRow.update(subtitle: directorySubtitle())

        let card = SettingsCardView()
        card.addRow(directoryRow)
        page.addCard(card, sectionTitle: "接收")
    }

    private func buildAutoAcceptSection() {
        autoAcceptSwitch.target = self
        autoAcceptSwitch.action = #selector(autoAcceptToggled)
        autoAcceptSwitch.setAccessibilityLabel("允许免配对接收")
        let autoAcceptRow = SettingsRowView(title: "允许免配对接收",
                                            subtitle: "窗口期内同一局域网设备无需 PIN 即可发送")
        autoAcceptRow.trailingStack.addArrangedSubview(autoAcceptSwitch)

        let duration = NSSegmentedControl(labels: ["5 分钟", "10 分钟", "30 分钟"],
                                          trackingMode: .selectOne,
                                          target: self,
                                          action: #selector(durationChanged))
        duration.controlSize = .small
        duration.setAccessibilityLabel("免配对窗口时长")
        durationControl = duration
        let durationRow = SettingsRowView(title: "窗口时长")
        durationRow.trailingStack.addArrangedSubview(duration)

        let restart = SettingsLinkButton.make("重新计时", target: self, action: #selector(restartWindow))
        restartButton = restart
        remainingLabel.alignment = .right
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)
        remainingLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        let remainingRow = SettingsRowView(title: "剩余")
        remainingRow.trailingStack.addArrangedSubview(remainingDot)
        remainingRow.trailingStack.addArrangedSubview(remainingLabel)
        remainingRow.trailingStack.addArrangedSubview(restart)

        let card = SettingsCardView()
        [autoAcceptRow, durationRow, remainingRow].forEach(card.addRow)
        page.addCard(card, sectionTitle: "免配对窗口")
    }

    private func buildTransferSection() {
        thresholdSwitch.target = self
        thresholdSwitch.action = #selector(thresholdToggled)
        thresholdSwitch.setAccessibilityLabel("体积阈值")
        thresholdField.alignment = .right
        thresholdField.font = SettingsStyle.rowValueFont
        thresholdField.controlSize = .small
        thresholdField.target = self
        thresholdField.action = #selector(thresholdFieldChanged)
        thresholdField.delegate = self
        thresholdField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        thresholdField.setAccessibilityLabel("体积阈值（MB）")
        let unit = MenuPanelLabel.text("MB", font: SettingsStyle.rowSubtitleFont,
                                       color: .secondaryLabelColor)
        let thresholdRow = SettingsRowView(title: "体积阈值",
                                           subtitle: "开启后，小于该体积的接收免输 PIN")
        thresholdRow.trailingStack.addArrangedSubview(thresholdSwitch)
        thresholdRow.trailingStack.addArrangedSubview(thresholdField)
        thresholdRow.trailingStack.addArrangedSubview(unit)

        let card = SettingsCardView()
        card.addRow(thresholdRow)
        page.addCard(card, sectionTitle: "传输")
    }

    /// 提示音 — 旧窗口的五个事件逐个成行（原型只画了总开关，这里按字段一一对应保留）
    private func buildSoundSection() {
        let card = SettingsCardView()
        for event in TransferPreferences.SoundEvent.allCases {
            let toggle = NSSwitch()
            toggle.target = self
            toggle.action = #selector(soundToggled(_:))
            toggle.setAccessibilityLabel(event.label)
            soundSwitches[event] = toggle
            let row = SettingsRowView(title: event.label)
            row.trailingStack.addArrangedSubview(toggle)
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "提示音")
    }

    // MARK: - 刷新

    override func refresh() {
        refreshValues()
        refreshUsage()
        startCountdown()
    }

    private func refreshValues() {
        for (event, toggle) in soundSwitches {
            toggle.state = preferences.soundEnabled(event) ? .on : .off
        }
        autoAcceptSwitch.state = preferences.autoAcceptEnabled ? .on : .off
        durationControl?.selectedSegment = TransferPreferences.windowOptions
            .firstIndex(of: preferences.autoAcceptMinutes) ?? 1
        durationControl?.isEnabled = preferences.autoAcceptEnabled
        restartButton?.isEnabled = preferences.autoAcceptEnabled

        let threshold = preferences.sizeThresholdMB
        thresholdSwitch.state = threshold > 0 ? .on : .off
        thresholdField.stringValue = String(threshold > 0 ? threshold : 10)
        thresholdField.isEnabled = threshold > 0

        refreshRemaining()
    }

    /// 免配对窗口剩余：活跃绿、到期橙、未开启灰
    private func refreshRemaining() {
        guard preferences.autoAcceptEnabled else {
            remainingDot.setColor(.tertiaryLabelColor)
            remainingLabel.stringValue = "未开启"
            restartButton?.isEnabled = false
            return
        }
        restartButton?.isEnabled = true
        if preferences.isWindowActive() {
            remainingDot.setColor(.systemGreen)
            remainingLabel.stringValue = preferences.windowRemainingText()
        } else {
            remainingDot.setColor(.systemOrange)
            remainingLabel.stringValue = "已到期"
        }
    }

    /// 刷新目录占用（后台扫描，避免大目录阻塞主线程）
    ///
    /// 放宽为 internal：接收目录扩展文件切换目录后要重算占用。
    func refreshUsage() {
        // 目录可能在扫描途中被切换：先记下扫描目标，回来时目录变了就丢弃这次结果
        let scanned = service.receiveDirectory
        usageText = "统计中…"
        directoryRow.update(subtitle: directorySubtitle())
        Task.detached(priority: .utility) { [weak self, service] in
            let summary = service.receiveDirectorySummary()
            let bytes = formatBytesFull(UInt64(max(0, summary.totalBytes)))
            await MainActor.run { [weak self] in
                guard let self, self.service.receiveDirectory == scanned else { return }
                self.usageText = "已接收 \(bytes) / \(summary.fileCount) 个文件"
                self.directoryRow.update(subtitle: self.directorySubtitle())
            }
        }
    }

    // MARK: - 倒计时

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopCountdown() } else { startCountdown() }
    }

    private func startCountdown() {
        guard countdownTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshRemaining() }
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - 动作

    @objc private func openReceiveDirectory() {
        let directory = service.receiveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func clearReceivedFiles() {
        let alert = NSAlert()
        alert.messageText = "清理接收目录？"
        alert.informativeText = "将删除 \(Self.displayPath(service.receiveDirectory)) 下的全部文件，"
            + "并清空对应的已完成记录。此操作不可撤销。"
        alert.addButton(withTitle: "清理")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        clearButton?.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.clearReceivedFiles()
            self.clearButton?.isEnabled = true
            self.logger.info("清理接收目录完成：\(result.removedFiles) 个文件")
            self.refreshUsage()
        }
    }

    @objc private func autoAcceptToggled() {
        let enabled = autoAcceptSwitch.state == .on
        preferences.autoAcceptEnabled = enabled
        if enabled {
            preferences.startWindow()
        } else {
            preferences.stopWindow()
        }
        durationControl?.isEnabled = enabled
        restartButton?.isEnabled = enabled
        refreshRemaining()
        logger.info("免配对窗口已\(enabled ? "开启" : "关闭")（\(preferences.autoAcceptMinutes) 分钟）")
    }

    @objc private func durationChanged() {
        guard let index = durationControl?.selectedSegment,
              TransferPreferences.windowOptions.indices.contains(index) else { return }
        preferences.autoAcceptMinutes = TransferPreferences.windowOptions[index]
        // 时长变化后立即按新时长重新计时
        if preferences.autoAcceptEnabled { preferences.startWindow() }
        refreshRemaining()
    }

    @objc private func restartWindow() {
        guard preferences.autoAcceptEnabled else { return }
        preferences.startWindow()
        refreshRemaining()
        logger.info("免配对窗口重新计时：\(preferences.autoAcceptMinutes) 分钟")
    }

    @objc private func thresholdToggled() {
        let enabled = thresholdSwitch.state == .on
        if enabled {
            let value = max(1, Int(thresholdField.stringValue) ?? 10)
            preferences.sizeThresholdMB = value
            thresholdField.stringValue = String(value)
        } else {
            preferences.sizeThresholdMB = 0
        }
        thresholdField.isEnabled = enabled
    }

    @objc private func thresholdFieldChanged() {
        guard thresholdSwitch.state == .on else { return }
        let value = max(1, Int(thresholdField.stringValue) ?? 10)
        thresholdField.stringValue = String(value)
        preferences.sizeThresholdMB = value
    }

    /// 路径展示统一缩成 ~ 开头
    ///
    /// 放宽为 internal：接收目录扩展文件拼副标题也要用。
    static func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    @objc private func soundToggled(_ sender: NSSwitch) {
        guard let event = soundSwitches.first(where: { $0.value === sender })?.key else { return }
        preferences.setSoundEnabled(sender.state == .on, for: event)
    }
}

// MARK: - 文本字段提交

extension SettingsTransferPane: NSTextFieldDelegate {

    /// 失焦也算提交，避免改完阈值直接点别处导致设置丢失
    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === thresholdField else { return }
        thresholdFieldChanged()
    }
}
