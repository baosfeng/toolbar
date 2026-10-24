import AppKit
import NetworkMonitorCore

// MARK: - Token 页

/// Token 消耗页 —— 菜单面板第 5 个 tab
///
/// 数据由 `HarnessUsageSnapshot` 注入（`update(_:)`），本视图不直接访问数据库或索引服务：
/// 打开面板时由控制器触发后台 `refreshIfNeeded()`，先渲染已有快照，索引完成靠
/// `AppEvents.harnessUsageChanged` 事件刷新。
/// 分区自上而下：hero 合计 + 环比 → 24 小时堆叠柱 → 三项分卡 → 复用率 / 请求数
/// → 按天趋势 → 模型分布 → 项目分布 → 本周 / 累计 → 页脚口径。
/// 下半部分四个区块可折叠（用户新增需求，见 `TokenCollapsibleSection`）。
/// 成员可见性：布局装配拆到 `TokenPaneView+Layout.swift`，相关属性由 private 放宽为 internal。
final class TokenPaneView: MenuPanelPaneView {

    // MARK: - 回调

    /// 点刷新（强制重新索引）
    var onRefresh: (() -> Void)?
    /// 内容高度变化（切换范围 / 索引状态影响布局）
    var onContentChanged: (() -> Void)?

    // MARK: - 交互状态

    private(set) var range: TokenRange = .today
    private(set) var hourMode: TokenHourMode = .today
    private(set) var trendMode: TokenTrendMode = .stack

    // MARK: - 数据

    private var snapshot: HarnessUsageSnapshot?

    // MARK: - 页头

    let rangeControl = TokenSegmentedControl(titles: TokenRange.allCases.map { $0.title })
    let refreshRow = TokenIconButtonRow(symbolName: "arrow.clockwise")
    let indexLabel = MenuPanelLabel.text("", font: TokenPaneStyle.metaFont,
                                                 color: TokenPaneStyle.secondaryText)

    // MARK: - 分区

    /// 折叠态持久化（注入；默认取全局存储，组合根可覆盖）
    let storage: any KeyValueStorage
    let hero = TokenHeroView()
    let hourChart = TokenHourlyChartView()
    lazy var hourHeader = TokenSectionHeaderView(title: "按小时", trailing: hourModeControl)
    let hourModeControl = TokenSegmentedControl(titles: TokenHourMode.allCases.map { $0.title })
    /// 与小时图左侧刻度区（40pt）对齐，避免 00/06 标签相对柱子左移
    let hourAxis = TokenAxisRowView(labels: ["00", "06", "12", "18", "23"], leadingInset: 40)
    let hourLegend = TokenLegendView(items: [
        TokenLegendItem(title: "缓存读", color: TokenPaneStyle.cacheColor),
        TokenLegendItem(title: "输出", color: TokenPaneStyle.outputColor),
        TokenLegendItem(title: "未缓存输入", color: TokenPaneStyle.inputColor),
        TokenLegendItem(title: "昨日同期", color: TokenPaneStyle.ghostColor),
    ])
    let chips = TokenChipRowView()
    let reuseChart = TokenSparklineView()
    lazy var reuseCard = TokenMiniCardView(title: "缓存复用率", chart: reuseChart)
    let requestChart = TokenRequestBarsView()
    lazy var requestCard = TokenMiniCardView(title: "请求数", chart: requestChart)
    let trendChart = TokenTrendChartView()
    let trendModeControl = TokenSegmentedControl(titles: TokenTrendMode.allCases.map { $0.title })
    let trendAxis = TokenAxisRowView(labels: ["", "", ""])
    let trendLegend = TokenLegendView(items: [
        TokenLegendItem(title: "缓存读", color: TokenPaneStyle.cacheColor),
        TokenLegendItem(title: "输出", color: TokenPaneStyle.outputColor),
        TokenLegendItem(title: "未缓存输入", color: TokenPaneStyle.inputColor),
        TokenLegendItem(title: "斜纹 = 无会话", color: nil),
    ])
    let donut = TokenDonutView()
    let modelList = TokenModelListView()
    let projectList = TokenProjectListView()
    let summary = TokenSummaryView()
    let footer = TokenFooterView()

    /// 按天趋势（默认折叠）
    lazy var trendSection = TokenCollapsibleSection(
        title: "按天",
        trailing: trendModeControl,
        content: trendBody,
        storage: storage,
        storageKey: "token.section.trend")

    /// 模型分布（默认折叠）
    lazy var modelSection = TokenCollapsibleSection(
        title: "按模型",
        content: modelBody,
        storage: storage,
        storageKey: "token.section.model")

    /// 项目分布（默认折叠）
    lazy var projectSection = TokenCollapsibleSection(
        title: "按项目",
        content: projectList,
        storage: storage,
        storageKey: "token.section.project")

    /// 本周 / 累计（默认折叠）
    lazy var totalsSection = TokenCollapsibleSection(
        title: "本周 / 累计",
        content: summary,
        storage: storage,
        storageKey: "token.section.totals")

    /// 按天趋势正文（图表 + 坐标 + 图例）
    lazy var trendBody: NSStackView = {
        let stack = NSStackView(views: [trendChart, trendAxis, trendLegend])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        pinWidth([trendChart, trendAxis, trendLegend], to: stack)
        return stack
    }()

    /// 模型分布正文（环形图 + 清单）
    lazy var modelBody: NSView = {
        donut.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            donut.widthAnchor.constraint(equalToConstant: TokenPaneStyle.donutSize),
            donut.heightAnchor.constraint(equalToConstant: TokenPaneStyle.donutSize),
        ])
        let row = NSStackView(views: [donut, modelList])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }()

    // MARK: - 状态页

    let dataStack = NSStackView()
    let loadingView = TokenLoadingView()
    lazy var emptyView = TokenEmptyView(onRetry: { [weak self] in self?.onRefresh?() })
    let unavailableView = TokenUnavailableView()

    // MARK: - 初始化

    init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildHeader()
        buildSections()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 键盘可达

    override var focusableRows: [MenuPanelRow] {
        var rows: [MenuPanelRow] = [refreshRow]
        rows.append(contentsOf: rangeControl.focusableRows)
        if !dataStack.isHidden {
            rows.append(contentsOf: hourModeControl.focusableRows)
            rows.append(contentsOf: trendModeControl.focusableRows)
            rows.append(trendSection.headerRow)
            rows.append(modelSection.headerRow)
            rows.append(projectSection.headerRow)
            rows.append(totalsSection.headerRow)
        }
        if !emptyView.isHidden { rows.append(emptyView.retryRow) }
        return rows
    }

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：切换范围 / 小时对比 / 趋势形态，覆盖多组界面状态
    func applyStateForSnapshot(range: TokenRange, hourMode: TokenHourMode, trendMode: TokenTrendMode) {
        self.range = range
        self.hourMode = hourMode
        self.trendMode = trendMode
        rangeControl.select(range.rawValue, notify: false)
        hourModeControl.select(hourMode.rawValue, notify: false)
        trendModeControl.select(trendMode.rawValue, notify: false)
        if let snapshot {
            applyState()
        }
    }
#endif

#if DEBUG
    /// 快照自证专用（仅 DEBUG）：展开全部折叠区块（不写持久化）
    func expandAllSectionsForSnapshot() {
        for section in [trendSection, modelSection, projectSection, totalsSection] {
            section.setExpandedForSnapshot(true)
        }
    }

    /// 快照自证专用（仅 DEBUG）：关键区块在页面坐标系中的 frame，用于与原型几何逐项对照
    func layoutMetricsForSnapshot() -> [(name: String, frame: NSRect)] {
        layoutSubtreeIfNeeded()
        let items: [(String, NSView)] = [
            ("hero", hero), ("hourChart", hourChart), ("chips", chips),
            ("reuseCard", reuseCard), ("requestCard", requestCard),
            ("trendChart", trendChart), ("donut", donut), ("modelList", modelList),
            ("projectList", projectList), ("summary", summary), ("footer", footer),
        ]
        return items.map { ($0.0, $0.1.convert($0.1.bounds, to: self)) }
    }
#endif

    // MARK: - 数据更新

    /// 应用最新快照（控制器 / 事件回调转发）
    func update(_ snapshot: HarnessUsageSnapshot) {
        self.snapshot = snapshot
        applyState()
    }

    // MARK: - 装配

    /// 页头下方的内容起点（buildHeader 里赋值为页头底边）
    var contentTopAnchor: NSLayoutYAxisAnchor?

    /// 把一组视图的宽度钉到容器宽度（图表视图无固有宽度，必须显式约束）
    func pinWidth(_ views: [NSView], to container: NSView) {
        for view in views {
            view.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }
    }

    private func wireActions() {
        refreshRow.onClick = { [weak self] in self?.onRefresh?() }
        rangeControl.onSelect = { [weak self] index in
            guard let self, let value = TokenRange(rawValue: index) else { return }
            self.range = value
            self.render()
        }
        hourModeControl.onSelect = { [weak self] index in
            guard let self, let value = TokenHourMode(rawValue: index) else { return }
            self.hourMode = value
            self.render()
        }
        trendModeControl.onSelect = { [weak self] index in
            guard let self, let value = TokenTrendMode(rawValue: index) else { return }
            self.trendMode = value
            self.render()
        }
    }

    // MARK: - 状态切换

    private func applyState() {
        guard let snapshot else { return }
        let available = snapshot.sourceAvailability.isAvailable
        let empty = TokenComparison.isEmpty(snapshot)
        let indexing = snapshot.indexingState.isIndexing
        let progress: HarnessIndexProgress? = {
            if case .indexing(let progress) = snapshot.indexingState { return progress }
            return nil
        }()

        unavailableView.isHidden = available
        guard available else {
            unavailableView.update(message: snapshot.sourceAvailability.displayMessage)
            dataStack.isHidden = true
            loadingView.isHidden = true
            emptyView.isHidden = true
            indexLabel.isHidden = true
            onContentChanged?()
            return
        }

        // 首轮索引尚未产出任何数据：显示带进度的加载态，不阻塞面板
        if empty && (indexing || snapshot.indexingState == .idle) {
            loadingView.update(progress: progress)
            loadingView.isHidden = false
            dataStack.isHidden = true
            emptyView.isHidden = true
            indexLabel.isHidden = true
            onContentChanged?()
            return
        }

        loadingView.isHidden = true
        // 空态用状态页替换数据区，避免「全 0 图表 + 空态说明」同时出现
        dataStack.isHidden = empty
        emptyView.isHidden = !empty
        if empty {
            indexLabel.isHidden = true
            onContentChanged?()
            return
        }
        indexLabel.isHidden = !indexing
        if indexing, let progress {
            indexLabel.stringValue = "索引中 \(progress.completedFiles)/\(progress.totalFiles) · 完成后自动刷新"
        }
        render()
    }

    // MARK: - 渲染

    private func render() {
        guard let snapshot else { return }
        let model = TokenPaneModel.make(snapshot: snapshot, range: range, hourMode: hourMode)
        let todayKey = HarnessTokenTimeWindow.dayKey(for: Date())

        hero.update(model)

        hourModeControl.select(hourMode.rawValue, notify: false)
        hourChart.update(today: model.hourly,
                        yesterday: model.yesterdayHourly,
                        currentHour: model.currentHour,
                        showsYesterday: hourMode == .compare)
        hourHeader.updateMeta(model.hourNote)

        chips.update(model.chips)
        reuseCard.update(value: model.reuseValue, tag: "近 30 天 · 按天")
        reuseChart.update(values: model.reuseSeries)
        requestCard.update(value: model.requestValue, tag: model.requestTag)
        requestChart.update(values: model.requestBars)

        trendModeControl.select(trendMode.rawValue, notify: false)
        trendSection.update(summary: model.trendSummary, expandedMeta: model.trendWindowLabel)
        trendChart.update(cells: model.trend, todayKey: todayKey, mode: trendMode)
        trendAxis.updateLabels(model.trendAxis)

        modelSection.update(summary: model.modelSummary, expandedMeta: model.modelMeta)
        projectSection.update(summary: model.projectSummary, expandedMeta: model.projectMeta)
        totalsSection.update(summary: model.totalsSummary, expandedMeta: "")
        donut.setCenterTitle("\(snapshot.daily.count) 天")
        donut.update(slices: model.models.map { ($0.share, TokenPaneStyle.modelColor($0.colorIndex)) })
        modelList.update(model.models)
        projectList.update(model.projects)
        summary.update(week: model.weekParts, total: model.totalParts)
        footer.update(lines: model.footer)
        onContentChanged?()
    }
}