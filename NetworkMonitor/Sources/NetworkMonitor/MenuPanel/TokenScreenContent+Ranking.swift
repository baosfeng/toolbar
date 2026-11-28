import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 排行屏

/// 排行屏：维度切换器 + 占比条 + Top 8 两行式行 + 汇总块 + 口径说明
///
/// 块顺序与 TokenScreen.blocks(for: .ranking) 一致。卡片高度与屏外框一致（撑到页脚上方），
/// 行高在 34…48 之间按可用高度自适应（不再 fillEqually 拉满：4 行时不再是大片空白）：
/// 多余高度优先给行，行满 48 后剩的留给卡片底部留白；行数 ≥ 8 时汇总块让位、≥ 7 时口径说明让位，
/// 保证任何行数下行高都不低于 34pt。
///
/// **Top 8 行由 DrawnRowList 一次画完**：改造前每行是一个 TokenRankingRowView
/// （色点 + 名称 + 值 + 占比 + 副文本 + 微条 = 6 个视图 + 10 条约束），8 行约 120 个视图。
@MainActor
final class TokenRankingScreenView: NSStackView {

    /// 当前维度（工具 / 项目 / 模型）——「全部」来源默认落在按工具
    private(set) var dimension: TokenDistroDimension = .tools
    /// 用户是否手动选过维度（没选过就跟随来源给默认值，选过就不再动）
    private var hasPickedDimension = false
    /// 维度切换回调：由 TokenPaneView 接到同一条 render 路径（不各走一套刷新）
    var onDimensionChange: (() -> Void)?

    /// 行数上限（标准 / 极致档都用满，省电档截断显示）
    ///
    /// 行不再预建视图，这条只是数据上限：切档只改「显示几行」，
    /// 省电切回标准时按同一份数据重算，不会出现「少一半行」且不自愈。
    static let maxRowCount = 8
    /// 当前档位允许的可见行数（标准 / 极致 8 行，省电 4 行）
    static var topRowCount: Int { min(maxRowCount, ThemeStyle.profile.rankingLimit) }
    /// 行高上下限（pt）
    ///
    /// 上限 64：项目/模型只有 2–3 个是单机常态（实测本机今日 3 个），
    /// 上限给 44 时卡片中段会空出 70pt+ 一片白，读作「内容没加载完」。
    /// 抬到 64 后 3 行恰好吃掉大部分余量；4 行以上按可用高度均分自然收敛，
    /// 8 行时由「汇总块 / 口径让位」+ 34pt 保底兜住，不会顶破卡高。
    static let minRowHeight: CGFloat = 34
    static let maxRowHeight: CGFloat = 64

    private let dimTitle = MenuPanelLabel.text("维度", font: TokenPaneStyle.axisFont,
                                              color: TokenPaneStyle.tertiaryText)
    let dimSegment = TokenSegmentedControl(titles: TokenDistroDimension.all.map { $0.segmentTitle },
                                          expands: true, style: .inline)
    // 以下块视图由 TokenScreenContent+Ranking+Snapshot.swift 的快照扩展读取（仅 DEBUG），
    // 跨文件访问必须放宽为 internal；它们只在本目录内使用，不对外暴露语义。
    let card = TokenBoxView(spacing: 3)
    let head = TokenCardHead(title: TokenDistroDimension.projects.title)
    let bar = TokenStackBarView(height: 8)
    /// 排行行 —— 整块 1 个视图，Top 8 由它一次画完
    let rowList = DrawnRowList()
    private let emptyRow = TokenKeyRowView()
    /// 汇总块：总 tok / 缓存读 / 未缓存 / 输出 / 请求数（取该维度合计，与占比分母同源）
    /// 汇总块行（跨文件访问：+Rows.swift 的 updateSummary 填值）
    let summaryRows = (0..<5).map { _ in TokenKeyRowView() }
    let summaryGrid: NSView
    /// 口径说明：单行 + 尾部省略，完整文案进悬停与读屏
    ///
    /// 原本给 4 行，但 385pt 卡高里 5 行数据时它实际被压成 1 行、还按词硬切（尾巴凭空消失）。
    /// 改成显式单行：头部信息保留（「口径：项目按会话 cwd 归属聚合…」），全文靠悬停补。
    let noteView = TokenNoteView(maxLines: 1)
    /// 底部留白（行高封顶后剩下的高度放这里，避免被其它块吸走而拉高行）
    let spacer = NSView()
    /// 行列表面板高度约束（跨文件：+Ranking+Layout.swift 的行高自适应要写它）
    var rowsHeight: NSLayoutConstraint?
    /// 留白高度约束（跨文件同上）
    var spacerHeight: NSLayoutConstraint?
    /// 行高自适应重入保护（跨文件同上）
    var isMeasuring = false

    init(cardHeight: CGFloat) {
        summaryGrid = TokenContentKit.twoColumn(summaryRows)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = PaneCardStyle.cardSpacing
        setAccessibilityRole(.group)
        dimSegment.setAccessibilityLabel("切换排行维度：工具 / 项目 / 模型")
        dimSegment.onSelect = { [weak self] index in
            guard let self else { return }
            self.dimension = Self.dimension(forIndex: index)
            self.hasPickedDimension = true
            self.onDimensionChange?()
        }
        buildCard(cardHeight: cardHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func buildCard(cardHeight: CGFloat) {
        let dimRow = NSStackView(views: [dimTitle, dimSegment])
        dimRow.orientation = .horizontal
        dimRow.alignment = .centerY
        dimRow.spacing = 6

        configureRowList()

        let rowsHeight = rowList.heightAnchor.constraint(equalToConstant: 0)
        rowsHeight.priority = .defaultHigh
        rowsHeight.isActive = true
        self.rowsHeight = rowsHeight

        spacer.translatesAutoresizingMaskIntoConstraints = false
        // 留白必须由 spacer 独占：其余块若同为默认 hugging，多出来的高度会被随机拉给某一块
        // （实测口径说明被拉高到 66pt、文字只画一行，行高反被压在 35pt）
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        let spacerHeight = spacer.heightAnchor.constraint(equalToConstant: 0)
        spacerHeight.priority = .defaultHigh
        spacerHeight.isActive = true
        self.spacerHeight = spacerHeight

        // 定高块一律 required hugging：多出来的高度只能进 spacer，不能被它们吸走；
        // 口径说明再叠一条 required 压缩阻力：否则它会被行列表挤成 1 行（实测尾巴被吃掉）
        for view in [dimRow, head, bar, emptyRow, summaryGrid, noteView] {
            view.setContentHuggingPriority(.required, for: .vertical)
        }
        noteView.setContentCompressionResistancePriority(.required, for: .vertical)
        // 顺序：维度段 → 卡头 → 占比条 → 行列表 → 余量 → 汇总 → 口径
        //
        // 余量（spacer）放在行列表与汇总之间，不放卡底：项目/模型只有 2–3 个时
        // （单机常见），余量放卡底会让整张卡下半截塌成一片空白，看起来像"内容没加载完"。
        // 放中间时它读作「列表区留白」，而汇总与口径永远贴卡底、与其它卡对齐。
        card.setRows([dimRow, head, bar, rowList, emptyRow, spacer, summaryGrid, noteView])
        card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
        addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        // 列表宽度跟卡片内容区走（行不是视图，宽度由列表按自身 bounds 分配）
        rowList.widthAnchor.constraint(equalTo: card.body.widthAnchor).isActive = true
    }

    /// 排行行的视觉规格 —— 与改造前 TokenRankingRowView 同一套令牌
    private func configureRowList() {
        rowList.rowSpacing = 2
        rowList.horizontalInset = 0
        rowList.elementGap = 6
        rowList.rowHeight = Self.maxRowHeight
        rowList.swatchSize = 6
        rowList.barHeight = 2
        rowList.titleFont = TokenPaneStyle.rowNameFont
        rowList.valueFont = TokenPaneStyle.rowValueFont
        rowList.secondaryFont = TokenPaneStyle.rowPercentFont
        rowList.detailFont = TokenPaneStyle.noteFont
        rowList.titleColor = TokenPaneStyle.secondaryText
        rowList.secondaryColor = TokenPaneStyle.tertiaryText
        rowList.detailColor = TokenPaneStyle.tertiaryText
        rowList.trackColor = TokenPaneStyle.trackColor
        rowList.barColor = TokenPaneStyle.trackColor
        rowList.highlightsHover = false
        // 行高由本屏 layout 显式给：hugging 压低、压缩阻力放开，别的块才抢不走行的高度
        rowList.setContentHuggingPriority(NSLayoutConstraint.Priority(100), for: .vertical)
        rowList.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        rowList.setAccessibilityLabel("排行列表")
    }

    // MARK: 行高自适应

    /// 按「可用高度 ÷ 可见行数」定行高（夹在 34…48），封顶后剩下的高度交给底部 spacer
    override func layout() {
        super.layout()
        updateRowHeights()
    }

    // MARK: 渲染

    /// 只搬运当前维度那一份分布行：颜色偏移与旧主面板一致（模型整体 +1 色）
    func update(model: TokenPaneModel) {
        // 「按工具」只在全部来源下成立（单源时只有一行，等于重复页头）
        let showsTools = model.displaySource == nil
        applyDimensionAvailability(showsTools: showsTools)
        if !hasPickedDimension {
            dimension = showsTools ? .tools : .projects
        } else if dimension == .tools && !showsTools {
            dimension = .projects
        }
        let rows: [TokenDistroRow]
        let totals: TokenDistroTotals
        switch dimension {
        case .tools:
            rows = model.tools
            totals = model.toolTotals
        case .projects:
            rows = model.projects
            totals = model.projectTotals
        case .models:
            rows = model.models
            totals = model.modelTotals
        }
        let copy = model.distroCopy
        // 模型维度整体错一色（与旧主面板一致），其余两段同序取色
        let offset = dimension == .models ? 1 : 0
        dimSegment.select(Self.index(for: dimension), notify: false)
        head.update(title: dimension.title, meta: copy.rangeTitle + " "
            + String(rows.count) + " 个")

        // 可见行数受渲染档限制（省电档 Top 4）；占比条与行用同一份切片，上下数据对得上
        let limit = Self.topRowCount
        let barRows = Array(rows.prefix(limit))
        bar.update(shares: barRows.map { $0.share },
                   colors: barRows.map { TokenPaneStyle.distroColor($0.colorIndex + offset) },
                   accessibility: dimension.barAccessibility(range: model.range),
                   tip: TokenDerive.stackBarTip(barRows, hiddenCount: rows.count - barRows.count))

        // 两行式：第一行「色点 + 名称 + 值 + 占比」，第二行「会话数 · 请求数 / provider」，底部微条
        rowList.rows = barRows.map { row in
            DrawnRowSpec(title: row.name,
                         value: row.amount,
                         progress: row.share,
                         detail: Self.metaText(row: row),
                         secondary: TokenFormatting.percent(row.share),
                         showsSwatch: true)
        }
        // 色点与占比条同一取色函数，行与条能一一对上（不再需要图例）
        rowList.rowSwatchColor = { index in
            guard index < barRows.count else { return nil }
            return TokenPaneStyle.distroColor(barRows[index].colorIndex + offset)
        }
        // 悬停文案仍由 Core 拼装（同名模型的 provider / 命中率只在悬停里给全）
        rowList.rowToolTip = { index in
            guard index < barRows.count else { return "" }
            return barRows[index].tip
        }
        rowList.isHidden = rows.isEmpty
        emptyRow.isHidden = !rows.isEmpty
        emptyRow.update(title: dimension.title, value: "暂无数据")
        bar.isHidden = rows.isEmpty

        // 行多时先让汇总块、再让口径说明让位，保证行高不低于 34pt
        // 判据用可见行数（受档位限制）而不是数据行数：省电档只显示 4 行时汇总块该留着
        let visibleRowCount = barRows.count
        summaryGrid.isHidden = visibleRowCount > 7
        noteView.isHidden = visibleRowCount > 7
        updateSummary(totals)
        // 卡面只放单行短口径；完整口径（含「去重 / 分母 / 跟随范围」）走悬停与读屏，
        // 否则 385pt 卡高里它会被压成 1 行再按词硬切、留下半句
        let fullNote: String
        switch dimension {
        case .tools: fullNote = TokenToolRanking.note(range: model.range)
        case .projects: fullNote = copy.projectsNote
        case .models: fullNote = copy.modelsNote
        }
        noteView.update(dimension.shortNote(range: model.range), full: fullNote)
        setAccessibilityLabel(dimension.cardAccessibility(range: model.range))
        layoutSubtreeIfNeeded()
        updateRowHeights()
    }

    // MARK: 辅助（行文案与维度映射见 TokenRankingRows.swift）

    /// 键盘可达：维度分段可聚焦（行本身是只读文本，不做点击）；隐藏的段不进焦点链
    var focusableRows: [MenuPanelRow] { dimSegment.focusableRows.filter { !$0.isHidden } }
}