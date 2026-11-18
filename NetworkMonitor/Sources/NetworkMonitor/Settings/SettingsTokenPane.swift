import AppKit
import NetworkMonitorCore

// MARK: - Token 用量设置页

/// Token 用量设置页 —— 数据源（目录 / zstd）+ 索引摘要 + 维护动作
///
/// 为什么需要这一页：Token 监控此前把会话目录硬编码成 ~/.dsh/sessions，
/// 换一台机器或换了 DSH 安装位置就读不到数据，而界面只会说「还没有可统计的会话」。
/// 这里给出三项：**能不能读**（zstd 状态）、**在读哪**（目录 + 来源）、
/// **读到了什么**（会话数 / 事件数 / 最近扫描时间），并配两个动作
/// （重新扫描＝全量清理后重建、清理历史数据＝只清不扫）。
final class SettingsTokenPane: SettingsPaneView {

    /// 跨文件访问：动作扩展（SettingsTokenPane+Actions.swift）要用
    let controller: SettingsTokenController
    let logger: LoggingService

    /// 目录行（跨文件访问：动作在 SettingsTokenPane+Actions.swift）
    let directoryRow = SettingsRowView(title: "数据目录")
    let directoryValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                  color: SettingsTheme.textPrimary)
    let directoryOriginLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                   color: SettingsTheme.textSecondary)
    var chooseDirectoryButton = NSButton()
    var resetDirectoryButton = NSButton()

    /// zstd 行
    let zstdRow = SettingsRowView(title: "解压工具")
    let zstdValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                             color: SettingsTheme.textPrimary)
    let zstdDot = SettingsStatusDotView()

    /// 索引摘要三行
    let sessionsRow = SettingsRowView(title: "会话数量")
    let sessionsValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textPrimary)
    let eventsRow = SettingsRowView(title: "索引事件")
    let eventsValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                               color: SettingsTheme.textPrimary)
    let scanTimeRow = SettingsRowView(title: "最近扫描")
    let scanTimeValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textPrimary)

    /// 最近一次渲染用的摘要（DEBUG 取证补事件数时复用其余字段）
    private var lastSummary: SettingsTokenController.Summary?

    /// 维护行（重新扫描 / 清理历史）
    let maintenanceRow = SettingsRowView(title: "维护",
                                         subtitle: "重新扫描会先清空索引再全量重建；清理历史可选范围并自动重扫")
    var rescanButton = NSButton()
    var clearButton = NSButton()

    init(controller: SettingsTokenController, logger: LoggingService = AppContext.shared.logger) {
        self.controller = controller
        self.logger = logger
        super.init(section: .token)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 构建

    override func buildContent() {
        buildSourceCard()
        buildIndexCard()
        buildMaintenanceCard()
        page.addNote("数据来自 DSH 会话日志（session*.jsonl.zstd）。换机器或改了 DSH 安装位置时，"
                     + "在这里指定新的会话目录即可；「重新扫描」会先清空本地索引再全量重建。")
    }

    private func buildSourceCard() {
        directoryValueLabel.lineBreakMode = .byTruncatingMiddle
        directoryValueLabel.maximumNumberOfLines = 1
        directoryValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        directoryValueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true

        let directoryStack = NSStackView(views: [directoryValueLabel, directoryOriginLabel])
        directoryStack.orientation = .vertical
        directoryStack.alignment = .trailing
        directoryStack.spacing = SettingsTheme.rowLabelSpacing
        directoryRow.trailingStack.addArrangedSubview(directoryStack)

        chooseDirectoryButton = SettingsLinkButton.make("选择…", target: self,
                                                        action: #selector(chooseSourceDirectory))
        chooseDirectoryButton.setAccessibilityLabel("选择 DSH 会话数据目录")
        resetDirectoryButton = SettingsLinkButton.make("恢复默认", target: self,
                                                       action: #selector(resetSourceDirectory))
        resetDirectoryButton.setAccessibilityLabel("恢复默认 DSH 会话数据目录")
        // 两个动作放在目录行下方一行：目录行右侧要留给路径本身
        let actionRow = SettingsRowView(title: "目录操作")
        actionRow.trailingStack.addArrangedSubview(chooseDirectoryButton)
        actionRow.trailingStack.addArrangedSubview(resetDirectoryButton)

        zstdValueLabel.lineBreakMode = .byTruncatingMiddle
        zstdValueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zstdValueLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        zstdRow.trailingStack.addArrangedSubview(zstdDot)
        zstdRow.trailingStack.addArrangedSubview(zstdValueLabel)

        let card = SettingsCardView()
        [directoryRow, actionRow, zstdRow].forEach(card.addRow)
        page.addCard(card, sectionTitle: "数据源")
    }

    private func buildIndexCard() {
        for label in [sessionsValueLabel, eventsValueLabel, scanTimeValueLabel] {
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        sessionsRow.trailingStack.addArrangedSubview(sessionsValueLabel)
        eventsRow.trailingStack.addArrangedSubview(eventsValueLabel)
        scanTimeRow.trailingStack.addArrangedSubview(scanTimeValueLabel)

        let card = SettingsCardView()
        [sessionsRow, eventsRow, scanTimeRow].forEach(card.addRow)
        page.addCard(card, sectionTitle: "索引")
    }

    private func buildMaintenanceCard() {
        rescanButton = SettingsLinkButton.make("重新扫描…", target: self,
                                               action: #selector(requestRescan))
        rescanButton.setAccessibilityLabel("重新扫描 Token 索引（先清空再全量重建，需二次确认）")
        clearButton = SettingsLinkButton.make("清理历史数据…", target: self,
                                              action: #selector(requestClearHistory),
                                              color: SettingsTheme.destructive)
        clearButton.setAccessibilityLabel("清理 Token 索引历史数据（可选全部 / 近 90 / 30 / 7 天，需二次确认）")
        maintenanceRow.trailingStack.addArrangedSubview(rescanButton)
        maintenanceRow.trailingStack.addArrangedSubview(clearButton)

        let card = SettingsCardView()
        card.addRow(maintenanceRow)
        page.addCard(card, sectionTitle: "维护")
    }

    // MARK: - 刷新

    override func refresh() {
        refreshSourceCard()
        // 先填内存里现成的读数（首帧不空），再异步补查库的事件数
        apply(controller.immediateSummary())
        controller.loadSummary { [weak self] summary in
            self?.apply(summary)
        }
    }

    private func refreshSourceCard() {
        let diagnostics = controller.diagnostics
        directoryValueLabel.stringValue = diagnostics.directoryPath.isEmpty
            ? "（尚未确定）" : diagnostics.directoryPath
        directoryValueLabel.toolTip = diagnostics.directoryPath
        directoryOriginLabel.stringValue = diagnostics.origin.displayName
        directoryValueLabel.setAccessibilityLabel("数据目录，" + diagnostics.origin.displayName)
        resetDirectoryButton.isEnabled = diagnostics.origin == .explicitPreference

        if let zstdPath = diagnostics.zstdPath {
            zstdDot.setColor(SettingsTheme.okInk)
            zstdValueLabel.stringValue = zstdPath
            zstdValueLabel.toolTip = zstdPath
            zstdValueLabel.setAccessibilityLabel("解压工具已就绪，" + zstdPath)
        } else {
            zstdDot.setColor(SettingsTheme.warnInk)
            zstdValueLabel.stringValue = diagnostics.zstdNote ?? "未找到 zstd"
            zstdValueLabel.toolTip = diagnostics.zstdNote
            zstdValueLabel.setAccessibilityLabel("解压工具缺失，" + (diagnostics.zstdNote ?? ""))
        }
        zstdValueLabel.textColor = diagnostics.isZstdReady ? SettingsTheme.textPrimary
                                                           : SettingsTheme.textSecondary
    }

    private func apply(_ summary: SettingsTokenController.Summary) {
        lastSummary = summary
        sessionsValueLabel.stringValue = "\(summary.indexedSessions) / \(summary.totalSessions)"
        sessionsValueLabel.setAccessibilityLabel(
            "已索引 \(summary.indexedSessions) 个会话，共发现 \(summary.totalSessions) 个")
        eventsValueLabel.stringValue = summary.eventCount.map { "\($0) 条" } ?? "…"
        scanTimeValueLabel.stringValue = SettingsTokenPane.scanTimeText(summary.lastScanAt,
                                                                        indexing: summary.isIndexing)
        // 目录无效或 zstd 缺失时，重建只会立刻失败：置灰而不是让用户白点一次
        let ready = controller.diagnostics.failureKind == nil
        rescanButton.isEnabled = ready
        // 事件数还没查回来（nil）时保持可点：不能因为「还在读」把入口变灰
        clearButton.isEnabled = summary.eventCount != 0
    }

#if DEBUG
    /// 取证专用：离屏渲染前同步补齐事件数（运行期不调用）
    func debugPrefillEventCount() {
        guard var summary = lastSummary else { return }
        summary.eventCount = controller.debugEventCount()
        apply(summary)
    }
#endif

    /// 「最近扫描」文案（索引中优先说明正在进行，避免把旧时间当成当前状态）
    static func scanTimeText(_ date: Date?, indexing: Bool) -> String {
        if indexing { return "索引中…" }
        guard let date else { return "尚未扫描" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
