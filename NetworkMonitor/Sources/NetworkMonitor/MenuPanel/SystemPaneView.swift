import AppKit
import NetworkMonitorCore

// MARK: - 系统页

/// 系统页 — 版2 紧凑首屏（四联 + 五卡 + 状态带）+ 面板内覆盖式二级详情页
///
/// 首屏下沉清单（五处都能点卡进二级页取回，无一丢失）：
/// - CPU 卡不画每核柱阵 → CPU 详情「每核」热力格（含逐核百分比）
/// - GPU 卡不画显存条（保留已用数值行）→ GPU 详情「已用显存」
/// - 内存卡不画四段数值行（只留四段条）→ 内存详情四段数值与占比
/// - 磁盘卡压成单行（忙% + 容量 + ›）→ 磁盘详情读写双序列 / IOPS / 繁忙度 / 容量
/// - 进程榜 Top-3 → Top-2，卡头「全部 ›」→ 压力详情（Top-10 + CPU 榜 / 内存榜切换）
///
/// 密度优先：界面只保留数值、单位与 ≤4 字标签；所有口径说明（采样方式、不可得原因）
/// 都写在卡片 `toolTip` 里，不占版面。
/// 刷新：控制器按 midInterval（5 秒）把 `SystemMonitoringService.snapshot` 推给
/// `update(snapshot:)`；曲线历史由 `updateHistories` 注入（60 点 1 秒采样）。
/// 空态：snapshot 整体或任一子项为 nil 时逐卡显示「—」，不隐藏整卡、不崩。
@MainActor
final class SystemPaneView: MenuPanelPaneView {

    /// 二级详情页（面板内覆盖，不弹窗）
    enum DetailPage {
        case cpu
        case gpu
        case memory
        case disk
        /// 压力 / 进程详情（首屏「全部 ›」入口，进程全量榜与两个榜单切换都在这里）
        case process

        /// 对应的详情页
        var detailPage: SystemDetailPaneView.Page {
            switch self {
            case .cpu: return .cpu
            case .gpu: return .gpu
            case .memory: return .memory
            case .disk: return .disk
            case .process: return .process
            }
        }
    }

    // 属性为 internal（默认）：拆出的 SystemPaneView+Cards / +Metrics 跨文件装配，
    // 同模块内无其他调用方。

    // MARK: 顶部四联

    // 一卡一族的语义色：CPU 蓝 / GPU 靛 / 内存 青绿 / 压力 橙（不再用强调色明度层级）
    let cpuTile = SystemHeroTileView(label: "CPU", lineColor: SystemPalette.cpu)
    let gpuTile = SystemHeroTileView(label: "GPU", lineColor: SystemPalette.gpu)
    let memoryTile = SystemHeroTileView(label: "内存", lineColor: SystemPalette.memoryActive)
    // 负载是就绪队列长度（非百分比），单位由数值自身表达，不画迷你曲线
    let loadTile = SystemHeroTileView(label: "负载", lineColor: SystemPalette.loadShort,
                                      showsSparkline: false)

    // MARK: CPU 卡（版2：不画每核柱阵，加卡内大号数值）

    let cpuCard = SystemCardView(title: "CPU", wash: SystemPalette.wash(.cpu))
    let cpuArea = SystemAreaChartView(height: 32)
    let cpuHero = SystemMetricValueView(fontSize: 23, unitFontSize: 9)
    // 卡头双图例（用户态 / 系统态）：与标题同行，不占新增行高
    let cpuSplit = SystemUsageSplitView()

    // MARK: GPU 卡（版2：不画显存条，保留已用数值行）

    let gpuCard = SystemCardView(title: "GPU", wash: SystemPalette.wash(.gpu))
    let gpuRing = SystemRingView(diameter: 40)
    let gpuSparkline = SystemSparklineView(lineColor: SystemPalette.gpu, height: 28)
    let gpuMemoryLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                             font: MenuPanelStyle.smallValueFont,
                                             color: SystemPalette.gpuInk)

    // MARK: 内存卡（版2：只留四段条）

    let memoryCard = SystemCardView(title: "内存", wash: SystemPalette.wash(.memory))
    let memoryBar = SystemStackedBarView()
    let pressureDot = SystemPressureDotView()

    // MARK: 磁盘卡（版2：压成单行 — 忙% + 容量 + ›）

    let diskCard = SystemCardView(title: "磁盘", wash: SystemPalette.wash(.disk))
    // 卡头繁忙度微条：30pt 宽的细条 + 「忙 xx%」，走磁盘族石墨（「忙」是设备占用率，属容量/水位一族）
    let diskBusyLabel = MenuPanelLabel.text(SystemPaneFormat.placeholder,
                                            font: MenuPanelStyle.smallValueFont,
                                            color: SystemPalette.diskInk)
    let diskBusyTrack = MenuPanelTrackView(fillColor: SystemPalette.disk, height: 3)

    // MARK: 压力卡（负载三线 + 进程榜 Top-2 + 「全部 ›」）

    let loadCard = SystemCardView(title: "压力", wash: SystemPalette.wash(.load))
    let loadChart = SystemLoadChartView()
    let loadNumbers = SystemLoadNumbersView()
    let processList = SystemProcessListView(rows: 2)
    let processAllButton = NSButton(title: "全部 ›", target: nil, action: nil)

    // MARK: 底部状态带（原温度卡下线后的形态）

    let stateBand = SystemStateBandView()

    // MARK: 首屏容器与详情页

    /// 首屏内容（四联 + 五卡 + 状态带）
    private let overviewStack = NSStackView()
    /// 二级详情页容器（覆盖式，不弹窗）
    let detailPane = SystemDetailPaneView()
    /// 首屏 / 详情互斥容器：hidden 的一侧由 NSStackView 折叠，高度只由可见侧决定
    private let rootStack = NSStackView()
    /// 当前详情页（nil = 首屏）
    private(set) var currentDetail: DetailPage?
    /// 进入详情前点击的卡片（返回时把键盘焦点还给它）
    private weak var lastOpenedCard: SystemCardView?
    /// 最近一帧快照（切详情页时立即用现有数据填充，不等下一次 tick）
    /// internal：SystemPaneView+Histories 的 syncDetailIfNeeded 跨文件读取
    var lastSnapshot: SystemMetricsSnapshot?

    /// 内容高度变化回调（进出详情页时面板要重算 popover 高度）
    var onContentHeightChange: (() -> Void)?
    /// 请求把面板滚动位置归零（进 / 出详情页都从顶部开始读）
    var onRequestScrollToTop: (() -> Void)?
    /// 请求把键盘焦点还给指定卡片（返回首屏时）
    var onRestoreCardFocus: ((SystemCardView) -> Void)?

    /// 是否正在看详情页（Esc 语义由面板根视图据此分流）
    var isShowingDetail: Bool { currentDetail != nil }

    /// 键盘可达卡片 — 首屏五张整卡可点（压力卡进「压力详情」）；详情页里交给返回键
    override var focusableCards: [any MenuPanelCardFocusable] {
        guard currentDetail == nil else { return [] }
        return [cpuCard, gpuCard, loadCard, memoryCard, diskCard]
    }

    // MARK: 曲线历史（二级详情页共用同一批 60 点数据）

    var cpuHistory: [Double] = []
    var cpuSystemHistory: [Double] = []
    var gpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var memoryWiredHistory: [Double] = []
    var memoryActiveHistory: [Double] = []
    var memoryCompressedHistory: [Double] = []
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []
    var loadShortHistory: [Double] = []
    var loadMediumHistory: [Double] = []
    var loadLongHistory: [Double] = []

    // MARK: - 初始化

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        overviewStack.orientation = .vertical
        overviewStack.alignment = .leading
        overviewStack.spacing = 8
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(overviewStack)
        rootStack.addArrangedSubview(detailPane)
        detailPane.isHidden = true
        detailPane.onBack = { [weak self] in self?.showOverview() }
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            overviewStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            detailPane.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
        ])

        overviewStack.addArrangedSubview(makeHeroRow())
        overviewStack.addArrangedSubview(makeCPUCard())
        overviewStack.addArrangedSubview(makeGPUCard())
        // 压力卡排在 GPU 之后：520pt 首屏要完整装下它（含 Top-2 进程）
        overviewStack.addArrangedSubview(makeLoadCard())
        overviewStack.addArrangedSubview(makeMemoryCard())
        overviewStack.addArrangedSubview(makeDiskCard())
        overviewStack.addArrangedSubview(stateBand)
        for subview in overviewStack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: overviewStack.widthAnchor).isActive = true
        }
        update(snapshot: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据更新

    /// 刷新快照 — nil 或子项为 nil 时对应卡片显示「—」（不隐藏、不崩）
    func update(snapshot: SystemMetricsSnapshot?) {
        lastSnapshot = snapshot
        updateCPU(snapshot?.cpu)
        updateGPU(snapshot?.gpu)
        updateLoad(snapshot?.load)
        updateProcesses(snapshot?.processes, memoryTotal: snapshot?.memory?.total)
        updateMemory(snapshot?.memory)
        updateDisk(snapshot?.disk)
        updateThermal(snapshot?.thermal)
        updateBattery(snapshot?.battery)
        updateWiFiLink(snapshot?.wifi)
        syncDetailIfNeeded()
    }

    // MARK: - 曲线历史
    //
    // 注入入口（updateHistory / updateHistories）与详情页同步已拆到
    // SystemPaneView+Histories.swift：主文件要容纳详情页导航，一并放置会超 15 KiB。

    // MARK: - 派生口径

    // 本段访问级别为 internal：五个 updateXxx 已拆分到 SystemPaneView+Metrics.swift，
    // 跨文件调用需放宽（同模块内除该扩展外无其他调用方）。

    /// 卡头补充：P/E 核数（无分组元数据时退化为总核数）
    func coreSummary(_ snapshot: CPUSnapshot) -> String {
        if snapshot.performanceCores > 0 || snapshot.efficiencyCores > 0 {
            return "\(snapshot.performanceCores)P · \(snapshot.efficiencyCores)E"
        }
        return "\(snapshot.perCore.count) 核"
    }

    /// 最近一次进程快照与物理内存总量（榜单渲染时复用，无需等下一帧）
    var processesSnapshot: ProcessResourceSnapshot?
    var processesMemoryTotal: UInt64?
    /// 最近一次温度与电池快照（状态带 toolTip 需要把两者口径合并成一段说明）
    var lastThermalSnapshot: ThermalSnapshot?
    var lastBatterySnapshot: BatterySnapshot?
    /// 最近一次 Wi-Fi 链路快照（状态带 toolTip 要把三段口径合并成一段说明）
    var lastWiFiSnapshot: WiFiLinkSnapshot?
    /// 采样周期（秒）— 详情页「采样」行与 CPU 副标题共用，跟随设置页偏好（不硬编码 1 秒）
    var sampleIntervalSeconds: Double?

    /// Core 压力枚举 → 徽标级别（未知按正常显示，避免整条消失）
    func pressureLevel(_ pressure: MemoryPressureLevel) -> SystemPressureDotView.Level {
        Self.level(for: pressure)
    }

    /// 压力枚举 → 徽标级别的静态版（详情页没有首屏实例可借，共用同一份映射）
    static func level(for pressure: MemoryPressureLevel) -> SystemPressureDotView.Level {
        if pressure == .critical { return .critical }
        if pressure == .warning { return .warning }
        return .normal
    }

    /// 0...1 钳制（非有限值归零）
    static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    // MARK: - 二级详情页导航

    /// 进入二级详情页 — 面板内覆盖式切换（不弹窗、不新增 tab）
    ///
    /// - Parameters:
    ///   - page: 目标详情页
    ///   - card: 触发进入的卡片（返回时把键盘焦点还给这张卡）
    func showDetail(_ page: DetailPage, from card: SystemCardView? = nil) {
        guard currentDetail != page else { return }
        currentDetail = page
        lastOpenedCard = card
        detailPane.show(page.detailPage)
        detailPane.isHidden = false
        overviewStack.isHidden = true
        // 用最近一帧数据立即填充，不等下一次 5 秒节拍
        syncDetailIfNeeded()
        onRequestScrollToTop?()
        onContentHeightChange?()
    }

    /// 返回首屏：滚动归零、焦点还给进入前的卡片
    func showOverview() {
        guard currentDetail != nil else { return }
        currentDetail = nil
        detailPane.isHidden = true
        overviewStack.isHidden = false
        onRequestScrollToTop?()
        if let lastOpenedCard {
            onRestoreCardFocus?(lastOpenedCard)
        }
        onContentHeightChange?()
    }
}
