import AppKit
import NetworkMonitorCore

// MARK: - 传输设置窗

/// 传输设置窗 — 提示音、免配对窗口、体积阈值、接收目录占用与清理
///
/// 设置全部写入注入的 `TransferPreferences`（`KeyValueStorage` 包装），
/// 目录统计与清理直接调用 `TransferService`，窗口本身不缓存业务状态。
@MainActor
final class TransferSettingsWindow: NSObject, NSWindowDelegate {

    private let preferences: TransferPreferences
    private let service: TransferService
    private let logger: LoggingService
    private let window: NSWindow

    // MARK: 控件

    private var soundSwitches: [TransferPreferences.SoundEvent: NSButton] = [:]
    private let autoAcceptCheckbox = NSButton(checkboxWithTitle: "开启免配对窗口（期间未配对设备直接接收）",
                                              target: nil, action: nil)
    private let durationControl = NSSegmentedControl(labels: ["5 分钟", "10 分钟", "30 分钟"],
                                                     trackingMode: .selectOne,
                                                     target: nil, action: nil)
    private let restartButton = NSButton(title: "重新计时", target: nil, action: nil)
    private let windowStatusLabel = NSTextField(labelWithString: "")
    private let thresholdCheckbox = NSButton(checkboxWithTitle: "小于", target: nil, action: nil)
    private let thresholdField = NSTextField()
    private let thresholdUnitLabel = NSTextField(labelWithString: "MB 的文件免配对码")
    private let usageLabel = NSTextField(labelWithString: "")
    private let directoryLabel = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "清理接收目录…", target: nil, action: nil)
    private var refreshTimer: Timer?

    // MARK: - 初始化

    init(preferences: TransferPreferences,
         service: TransferService,
         logger: LoggingService = AppContext.shared.logger) {
        self.preferences = preferences
        self.service = service
        self.logger = logger
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "传送设置"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.contentView = buildContentView()
        refreshValues()
        startRefreshTimer()
    }

    /// 打开设置窗
    func show() {
        refreshValues()
        refreshUsage()
        startRefreshTimer()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// 关闭设置窗（同时停掉每秒刷新）
    func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        window.orderOut(nil)
    }

    // MARK: - 界面

    private func buildContentView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        stack.addArrangedSubview(Self.sectionLabel("提示音"))
        let soundRow = NSStackView()
        soundRow.orientation = .horizontal
        soundRow.spacing = 12
        for event in TransferPreferences.SoundEvent.allCases {
            let checkbox = NSButton(checkboxWithTitle: event.label, target: self,
                                    action: #selector(soundToggled))
            soundSwitches[event] = checkbox
            soundRow.addArrangedSubview(checkbox)
        }
        stack.addArrangedSubview(soundRow)

        stack.addArrangedSubview(Self.separator())
        stack.addArrangedSubview(Self.sectionLabel("免配对窗口"))
        stack.addArrangedSubview(autoAcceptCheckbox)
        autoAcceptCheckbox.target = self
        autoAcceptCheckbox.action = #selector(autoAcceptToggled)

        let durationRow = NSStackView(views: [durationControl, restartButton])
        durationRow.orientation = .horizontal
        durationRow.spacing = 8
        durationControl.target = self
        durationControl.action = #selector(durationChanged)
        restartButton.target = self
        restartButton.action = #selector(restartWindow)
        restartButton.bezelStyle = .rounded
        durationControl.segmentStyle = .rounded
        stack.addArrangedSubview(durationRow)
        styleSecondaryLabel(windowStatusLabel)
        stack.addArrangedSubview(windowStatusLabel)

        stack.addArrangedSubview(Self.separator())
        stack.addArrangedSubview(Self.sectionLabel("体积阈值"))
        let thresholdRow = NSStackView(views: [thresholdCheckbox, thresholdField, thresholdUnitLabel])
        thresholdRow.orientation = .horizontal
        thresholdRow.spacing = 6
        thresholdCheckbox.target = self
        thresholdCheckbox.action = #selector(thresholdToggled)
        thresholdField.target = self
        thresholdField.action = #selector(thresholdFieldChanged)
        thresholdField.alignment = .right
        thresholdField.widthAnchor.constraint(equalToConstant: 56).isActive = true
        styleSecondaryLabel(thresholdUnitLabel)
        stack.addArrangedSubview(thresholdRow)

        stack.addArrangedSubview(Self.separator())
        stack.addArrangedSubview(Self.sectionLabel("接收目录"))
        usageLabel.font = NSFont.systemFont(ofSize: 12.5)
        stack.addArrangedSubview(usageLabel)
        directoryLabel.font = NSFont.systemFont(ofSize: 11)
        directoryLabel.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(directoryLabel)
        clearButton.target = self
        clearButton.action = #selector(clearReceivedFiles)
        clearButton.bezelStyle = .rounded
        stack.addArrangedSubview(clearButton)

        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return stack
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.62)
        return label
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 440).isActive = true
        return box
    }

    private func styleSecondaryLabel(_ label: NSTextField) {
        label.font = NSFont.systemFont(ofSize: 11.5)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.72)
        label.lineBreakMode = .byTruncatingTail
    }

    // MARK: - 刷新

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshWindowStatus() }
        }
    }

    private func refreshValues() {
        for (event, checkbox) in soundSwitches {
            checkbox.state = preferences.soundEnabled(event) ? .on : .off
        }
        autoAcceptCheckbox.state = preferences.autoAcceptEnabled ? .on : .off
        let minutes = preferences.autoAcceptMinutes
        durationControl.selectedSegment = TransferPreferences.windowOptions.firstIndex(of: minutes) ?? 1
        durationControl.isEnabled = preferences.autoAcceptEnabled
        restartButton.isEnabled = preferences.autoAcceptEnabled

        let threshold = preferences.sizeThresholdMB
        thresholdCheckbox.state = threshold > 0 ? .on : .off
        thresholdField.stringValue = String(threshold > 0 ? threshold : 10)
        thresholdField.isEnabled = threshold > 0
        thresholdUnitLabel.textColor = threshold > 0
            ? NSColor.labelColor.withAlphaComponent(0.72)
            : NSColor.labelColor.withAlphaComponent(0.4)

        directoryLabel.stringValue = "路径：\(preferencesReceiveDirectoryPath)"
        refreshWindowStatus()
    }

    /// 每秒刷新免配对剩余时间
    private func refreshWindowStatus() {
        guard preferences.autoAcceptEnabled else {
            windowStatusLabel.stringValue = "未开启：未配对设备需要输入 PIN"
            return
        }
        if preferences.isWindowActive() {
            let text = preferences.windowRemainingText()
            windowStatusLabel.stringValue = "免配对剩余 \(text)"
            windowStatusLabel.textColor = .systemOrange
        } else {
            windowStatusLabel.stringValue = "已到期：回到 PIN 确认（点「重新计时」延长）"
            windowStatusLabel.textColor = .secondaryLabelColor
        }
    }

    /// 刷新目录占用（异步读取，避免阻塞主线程）
    private func refreshUsage() {
        usageLabel.stringValue = "统计中…"
        Task { [weak self] in
            guard let self else { return }
            let summary = self.service.receiveDirectorySummary()
            let bytesText = formatBytesFull(UInt64(max(0, summary.totalBytes)))
            await MainActor.run {
                self.usageLabel.stringValue = "已接收文件占用 \(bytesText) / 共 \(summary.fileCount) 个"
            }
        }
    }

    private var preferencesReceiveDirectoryPath: String {
        service.receiveDirectory.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    // MARK: - 动作

    @objc private func soundToggled(_ sender: NSButton) {
        guard let event = soundSwitches.first(where: { $0.value === sender })?.key else { return }
        preferences.setSoundEnabled(sender.state == .on, for: event)
    }

    @objc private func autoAcceptToggled() {
        let enabled = autoAcceptCheckbox.state == .on
        preferences.autoAcceptEnabled = enabled
        if enabled {
            preferences.startWindow()
        } else {
            preferences.stopWindow()
        }
        durationControl.isEnabled = enabled
        restartButton.isEnabled = enabled
        refreshWindowStatus()
        logger.info("免配对窗口已\(enabled ? "开启" : "关闭")（\(preferences.autoAcceptMinutes) 分钟）")
    }

    @objc private func durationChanged() {
        let index = durationControl.selectedSegment
        guard TransferPreferences.windowOptions.indices.contains(index) else { return }
        preferences.autoAcceptMinutes = TransferPreferences.windowOptions[index]
        // 时长变化后立即按新时长重新计时
        if preferences.autoAcceptEnabled {
            preferences.startWindow()
        }
        refreshWindowStatus()
    }

    @objc private func restartWindow() {
        guard preferences.autoAcceptEnabled else { return }
        preferences.startWindow()
        refreshWindowStatus()
        logger.info("免配对窗口重新计时：\(preferences.autoAcceptMinutes) 分钟")
    }

    @objc private func thresholdToggled() {
        let enabled = thresholdCheckbox.state == .on
        if enabled {
            let value = max(1, Int(thresholdField.stringValue) ?? 10)
            preferences.sizeThresholdMB = value
            thresholdField.stringValue = String(value)
        } else {
            preferences.sizeThresholdMB = 0
        }
        thresholdField.isEnabled = enabled
        refreshValues()
    }

    @objc private func thresholdFieldChanged() {
        guard thresholdCheckbox.state == .on else { return }
        let value = max(1, Int(thresholdField.stringValue) ?? 10)
        thresholdField.stringValue = String(value)
        preferences.sizeThresholdMB = value
    }

    @objc private func clearReceivedFiles() {
        let alert = NSAlert()
        alert.messageText = "清理接收目录？"
        alert.informativeText = "将删除「局域网互传」目录下的全部文件，并清空对应的已完成记录。此操作不可撤销。"
        alert.addButton(withTitle: "清理")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        clearButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            let result = await self.service.clearReceivedFiles()
            await MainActor.run {
                self.clearButton.isEnabled = true
                self.refreshUsage()
                self.logger.info("清理接收目录完成：\(result.removedFiles) 个文件")
            }
        }
    }
}
