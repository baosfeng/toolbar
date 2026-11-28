import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign

// MARK: - Token 用量设置页

/// Token 用量设置页 —— 来源清单（每源一行）+ 自动监控 + 索引与维护
///
/// 为什么从「一行目录」改成「一份清单」：多来源接入后目录不再只有一处，
/// 一个全局目录输入框表达不了「Claude Code 在这、Codex 在那、Gemini 没装」。
/// 每源一行 = 状态点 + 名称 + 路径/规模 + 启用开关 + 行内「选择目录…」，
/// 维护动作（重扫 / 清理）仍集中一处，用来源下拉选目标，不在每行挂一个菜单。
final class SettingsTokenPane: SettingsPaneView {

    /// 跨文件访问：动作扩展（SettingsTokenPane+Actions.swift）要用
    let controller: SettingsTokenController
    let logger: LoggingService

    // MARK: 数据来源卡（装配与刷新在 SettingsTokenSourcesCard.swift）

    /// 自动监控行（「数据来源」卡首行；装配在那个扩展文件里）
    let autoRow = SettingsRowView(
        title: "后台自动监控",
        subtitle: "默认关闭；首次启用任一来源时自动打开（可在下方随时关掉）")
    let autoSwitch = NSSwitch()
    let intervalControl = NSPopUpButton(frame: .zero, pullsDown: false)

    /// 每源一行（顺序 = TokenSourceID.allCases）
    ///
    /// 装配与填入方在 SettingsTokenSourcesCard.swift，跨文件写入故去掉 private(set)。
    var sourceRows: [TokenSourceID: SettingsTokenSourceRowView] = [:]

    // MARK: 解压工具

    /// zstd 行：只影响 zstd 压缩的会话文件（DSH / Zed），其余来源不依赖它
    let zstdRow = SettingsRowView(title: "解压工具",
                                  subtitle: "只与 DSH / Zed 有关（这两家的会话是 zstd 压缩的）；其余来源不依赖它")
    let zstdValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                             color: SettingsTheme.textPrimary)
    let zstdDot = SettingsStatusDotView()

    // MARK: 索引

    let sessionsRow = SettingsRowView(title: "会话数量")
    let sessionsValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textPrimary)
    let eventsRow = SettingsRowView(title: "索引事件")
    let eventsValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                               color: SettingsTheme.textPrimary)
    let scanTimeRow = SettingsRowView(title: "最近扫描")
    let scanTimeValueLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textPrimary)
    /// 按来源分组的一行（名称 → 「N 会话 / M 事件」）
    private(set) var sourceIndexRows: [TokenSourceID: SettingsRowView] = [:]
    private var sourceIndexValues: [TokenSourceID: NSTextField] = [:]

    /// 最近一次渲染用的摘要（DEBUG 取证补事件数时复用其余字段）
    private var lastSummary: SettingsTokenController.Summary?
    /// 最近一次读到的来源读数（动作里读当前状态，不重复查库；写入方在来源卡扩展文件）
    var readings: [TokenSourceID: SettingsTokenController.SourceReading] = [:]

    // MARK: 维护

    /// 目标来源下拉（0 = 全部来源）
    let sourceControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let maintenanceRow = SettingsRowView(
        title: "维护",
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
        addSourceNote()
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
        // 卡首行放解压工具：它是索引能力的一部分（缺 zstd 时 DSH / Zed 只能降级），
        // 挂在来源清单里会被读成「第 8 个来源」
        card.addRow(zstdRow)
        [sessionsRow, eventsRow, scanTimeRow].forEach(card.addRow)
        // 按来源分组的规模：每源一行，没索引过的来源写「未索引」而不是省略（省略会让人以为没有这个来源）
        for source in TokenSourceID.allCases {
            let value = MenuPanelLabel.text("—", font: SettingsTheme.rowValueFont,
                                            color: SettingsTheme.textPrimary)
            value.alignment = .right
            value.setContentHuggingPriority(.required, for: .horizontal)
            let row = SettingsRowView(title: source.displayName)
            row.trailingStack.addArrangedSubview(value)
            sourceIndexRows[source] = row
            sourceIndexValues[source] = value
            card.addRow(row)
        }
        page.addCard(card, sectionTitle: "索引")
    }

    private func buildMaintenanceCard() {
        sourceControl.controlSize = .small
        sourceControl.removeAllItems()
        sourceControl.addItem(withTitle: "全部来源")
        for source in TokenSourceID.allCases { sourceControl.addItem(withTitle: source.displayName) }
        sourceControl.target = self
        sourceControl.action = #selector(maintenanceSourceChanged)
        sourceControl.setAccessibilityLabel("维护动作的目标来源")
        SettingsControlChrome.applyStandardHeight(to: sourceControl)

        let sourceRow = SettingsRowView(title: "目标来源",
                                        subtitle: "重扫与清理都按这里选中的来源执行")
        sourceRow.trailingStack.addArrangedSubview(sourceControl)

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
        card.addRow(sourceRow)
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
        // 来源行与自动监控控件由来源卡扩展文件刷新，这里只按固定顺序拼三块
        refreshSourceRows()
        refreshZstdRow()
        refreshSourceIndexRows()
    }

    private func refreshZstdRow() {
        let diagnostics = controller.diagnostics
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

    private func refreshSourceIndexRows() {
        let counts = controller.sourceCounts()
        for source in TokenSourceID.allCases {
            let count = counts.first { $0.source == source }
            let text: String
            if let count, count.sessionCount > 0 || count.eventCount > 0 {
                text = String(count.sessionCount) + " 会话 / " + TokenFormatting.grouped(count.eventCount) + " 事件"
            } else {
                text = "未索引"
            }
            sourceIndexValues[source]?.stringValue = text
            sourceIndexRows[source]?.trailingStack.setAccessibilityLabel(source.displayName + "，" + text)
        }
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