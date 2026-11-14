import AppKit
import NetworkMonitorCore
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

    /// 当前维度（项目 / 模型）
    private(set) var dimension: TokenDistroDimension = .projects
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
    static let minRowHeight: CGFloat = 34
    static let maxRowHeight: CGFloat = 48

    private let dimTitle = MenuPanelLabel.text("维度", font: TokenPaneStyle.axisFont,
                                              color: TokenPaneStyle.tertiaryText)
    let dimSegment = TokenSegmentedControl(titles: ["项目", "模型"], expands: true,
                                                   style: .inline)
    // 以下块视图由 TokenScreenContent+Ranking+Snapshot.swift 的快照扩展读取（仅 DEBUG），
    // 跨文件访问必须放宽为 internal；它们只在本目录内使用，不对外暴露语义。
    let card = TokenBoxView(spacing: 3)
    let head = TokenCardHead(title: TokenDistroDimension.projects.title)
    let bar = TokenStackBarView(height: 8)
    /// 排行行 —— 整块 1 个视图，Top 8 由它一次画完
    let rowList = DrawnRowList()
    private let emptyRow = TokenKeyRowView()
    /// 汇总块：总 tok / 缓存读 / 未缓存 / 输出 / 请求数（取该维度合计，与占比分母同源）
    private let summaryRows = (0..<5).map { _ in TokenKeyRowView() }
    let summaryGrid: NSView
    let noteView = TokenNoteView(maxLines: 4)
    /// 底部留白（行高封顶后剩下的高度放这里，避免被其它块吸走而拉高行）
    let spacer = NSView()
    private var rowsHeight: NSLayoutConstraint?
    private var spacerHeight: NSLayoutConstraint?
    private var isMeasuring = false

    init(cardHeight: CGFloat) {
        summaryGrid = TokenContentKit.twoColumn(summaryRows)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = PaneCardStyle.cardSpacing
        setAccessibilityRole(.group)
        dimSegment.setAccessibilityLabel("切换排行维度：项目 / 模型")
        dimSegment.onSelect = { [weak self] index in
            guard let self else { return }
            self.dimension = Self.dimension(forIndex: index)
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

        // 定高块一律 required hugging：多出来的高度只能进 spacer，不能被它们吸走
        for view in [dimRow, head, bar, emptyRow, summaryGrid, noteView] {
            view.setContentHuggingPriority(.required, for: .vertical)
        }
        card.setRows([dimRow, head, bar, rowList, emptyRow, summaryGrid, noteView, spacer])
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

    private func updateRowHeights() {
        guard !isMeasuring, card.bounds.height > 0 else { return }
        let visible = rowList.rows.count
        guard visible > 0 else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let body = card.body
        // 注意要排除 spacer 自己：把它的当前高度算进 used 会形成自反馈（行高被压在 35pt 不动）
        let siblings = body.arrangedSubviews.filter {
            $0 !== rowList && $0 !== spacer && !$0.isHidden
        }
        // 可见段之间的间距：兄弟块 N 个 + 行列表 + spacer 自身
        let gaps = CGFloat(siblings.count + 1) * body.spacing
        let used = siblings.reduce(CGFloat(0)) { $0 + $1.frame.height } + gaps
        let available = max(0, body.bounds.height - used)
        // 行间距从可用高度里先扣，再均分给行——与改造前 fillEqually 的行高口径一致
        // （否则 2 行时行高会比旧版多 1pt，行高台账对不上）
        let spacing = rowList.rowSpacing
        let usable = max(0, available - spacing * CGFloat(max(visible - 1, 0)))
        let rowHeight = min(Self.maxRowHeight,
                            max(Self.minRowHeight, usable / CGFloat(visible)))
        if abs(rowList.rowHeight - rowHeight) > 0.5 {
            rowList.rowHeight = rowHeight
        }
        let total = DrawnRowLayout.contentHeight(rowCount: visible,
                                                 rowHeight: rowHeight,
                                                 rowSpacing: rowList.rowSpacing)
        if let rowsHeight, abs(rowsHeight.constant - total) > 0.5 {
            rowsHeight.constant = total
        }
        if abs((spacerHeight?.constant ?? -1) - max(0, available - total)) > 0.5 {
            spacerHeight?.constant = max(0, available - total)
        }
    }

    // MARK: 渲染

    /// 只搬运当前维度那一份分布行：颜色偏移与旧主面板一致（模型整体 +1 色）
    func update(model: TokenPaneModel) {
        let rows = dimension == .projects ? model.projects : model.models
        let totals = dimension == .projects ? model.projectTotals : model.modelTotals
        let copy = model.distroCopy
        let offset = dimension == .projects ? 0 : 1
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
        noteView.update(dimension == .projects ? copy.projectsNote : copy.modelsNote)
        setAccessibilityLabel(dimension.cardAccessibility(range: model.range))
        layoutSubtreeIfNeeded()
        updateRowHeights()
    }

    private func updateSummary(_ totals: TokenDistroTotals) {
        let items: [(String, String)] = [
            ("总 tok", TokenFormatting.tokens(totals.totalTokens)),
            ("缓存读", TokenFormatting.tokens(totals.cacheRead)),
            ("未缓存", TokenFormatting.tokens(totals.uncached)),
            ("输出", TokenFormatting.tokens(totals.output)),
            ("请求数", TokenFormatting.grouped(totals.requestCount)),
        ]
        for (index, row) in summaryRows.enumerated() where index < items.count {
            row.update(title: items[index].0, value: items[index].1)
        }
    }

    // MARK: 辅助

    /// 维度 → 分段下标（分段只两段，顺序固定：项目 / 模型）
    static func index(for dimension: TokenDistroDimension) -> Int {
        dimension == .projects ? 0 : 1
    }

    static func dimension(forIndex index: Int) -> TokenDistroDimension {
        index == 0 ? .projects : .models
    }

    /// 第二行：项目给「会话数 · 请求数」，模型给「provider · 请求数」
    static func metaText(row: TokenDistroRow) -> String {
        let requests = TokenFormatting.grouped(row.requestCount) + " 次请求"
        if row.sessionCount > 0 {
            return String(row.sessionCount) + " 会话 · " + requests
        }
        let provider = row.provider.isEmpty ? "未记录 provider" : "provider " + row.provider
        return provider + " · " + requests
    }

    /// 键盘可达：维度分段可聚焦（行本身是只读文本，不做点击）
    var focusableRows: [MenuPanelRow] { dimSegment.focusableRows }
#if DEBUG
    /// 快照自证：直接切维度（不回调，避免取证过程触发整页刷新）
    ///
    /// 留在主类里是因为它要写 private(set) 的 dimension；其余快照接口
    /// 只读，拆在 TokenScreenContent+Ranking+Snapshot.swift。
    func setDimensionForSnapshot(_ dimension: TokenDistroDimension) {
        self.dimension = dimension
    }
#endif
}