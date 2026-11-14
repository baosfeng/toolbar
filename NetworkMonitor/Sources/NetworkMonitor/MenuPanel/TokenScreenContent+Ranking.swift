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
@MainActor
final class TokenRankingScreenView: NSStackView {

    /// 当前维度（项目 / 模型）
    private(set) var dimension: TokenDistroDimension = .projects
    /// 维度切换回调：由 TokenPaneView 接到同一条 render 路径（不各走一套刷新）
    var onDimensionChange: (() -> Void)?

    /// 预建行数上限（标准 / 极致档都用满，省电档截断显示）
    ///
    /// 预建只建一次、数量固定，切档只改「显示几行」——预建按档位建会让「省电切回标准」
    /// 少一半行视图，且不会自愈。
    static let maxRowCount = 8
    /// 当前档位允许的可见行数（标准 / 极致 8 行，省电 4 行）
    static var topRowCount: Int { min(maxRowCount, ThemeStyle.profile.rankingLimit) }
    /// 行高上下限（pt）
    static let minRowHeight: CGFloat = 34
    static let maxRowHeight: CGFloat = 48

    private let dimTitle = MenuPanelLabel.text("维度", font: TokenPaneStyle.axisFont,
                                              color: TokenPaneStyle.tertiaryText)
    private let dimSegment = TokenSegmentedControl(titles: ["项目", "模型"], expands: true,
                                                   style: .inline)
    private let card = TokenBoxView(spacing: 3)
    private let head = TokenCardHead(title: TokenDistroDimension.projects.title)
    private let bar = TokenStackBarView(height: 8)
    private let rowsStack = NSStackView()
    private let rowViews = (0..<TokenRankingScreenView.maxRowCount).map { _ in TokenRankingRowView() }
    private let emptyRow = TokenKeyRowView()
    /// 汇总块：总 tok / 缓存读 / 未缓存 / 输出 / 请求数（取该维度合计，与占比分母同源）
    private let summaryRows = (0..<5).map { _ in TokenKeyRowView() }
    private let summaryGrid: NSView
    private let noteView = TokenNoteView(maxLines: 4)
    /// 底部留白（行高封顶后剩下的高度放这里，避免被其它块吸走而拉高行）
    private let spacer = NSView()
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

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 2
        // 行栈高度由「行高自适应」显式给（750 约束）：hugging 给低值，否则会停在自然高（4×34）
        rowsStack.setContentHuggingPriority(NSLayoutConstraint.Priority(100), for: .vertical)
        for row in rowViews {
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
        let rowsHeight = rowsStack.heightAnchor.constraint(equalToConstant: 0)
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
        card.setRows([dimRow, head, bar, rowsStack, emptyRow, summaryGrid, noteView, spacer])
        card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
        addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    // MARK: 行高自适应

    /// 按「可用高度 ÷ 可见行数」定行高（夹在 34…48），封顶后剩下的高度交给底部 spacer
    override func layout() {
        super.layout()
        updateRowHeights()
    }

    private func updateRowHeights() {
        guard !isMeasuring, card.bounds.height > 0 else { return }
        let visible = rowViews.filter { !$0.isHidden }.count
        guard visible > 0 else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let body = card.body
        // 注意要排除 spacer 自己：把它的当前高度算进 used 会形成自反馈（行高被压在 35pt 不动）
        let siblings = body.arrangedSubviews.filter {
            $0 !== rowsStack && $0 !== spacer && !$0.isHidden
        }
        // 可见段之间的间距：兄弟块 N 个 + 行栈 + spacer 自身
        let gaps = CGFloat(siblings.count + 1) * body.spacing
        let used = siblings.reduce(CGFloat(0)) { $0 + $1.frame.height } + gaps
        let available = max(0, body.bounds.height - used)
        let rowHeight = min(Self.maxRowHeight,
                            max(Self.minRowHeight, available / CGFloat(visible)))
        let rowsTotal = rowHeight * CGFloat(visible)
        if let rowsHeight, abs(rowsHeight.constant - rowsTotal) > 0.5 {
            rowsHeight.constant = rowsTotal
        }
        if abs((spacerHeight?.constant ?? -1) - max(0, available - rowsTotal)) > 0.5 {
            spacerHeight?.constant = max(0, available - rowsTotal)
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

        for (index, view) in rowViews.enumerated() {
            if index < min(rows.count, limit) {
                view.isHidden = false
                // 色点与占比条同一取色函数，行与条能一一对上（不再需要图例）
                view.update(row: rows[index],
                            swatchColor: TokenPaneStyle.distroColor(rows[index].colorIndex + offset))
            } else {
                view.isHidden = true
            }
        }
        rowsStack.isHidden = rows.isEmpty
        emptyRow.isHidden = !rows.isEmpty
        emptyRow.update(title: dimension.title, value: "暂无数据")
        bar.isHidden = rows.isEmpty

        // 行多时先让汇总块、再让口径说明让位，保证行高不低于 34pt
        // 判据用**可见行数**（受档位限制）而不是数据行数：省电档只显示 4 行时汇总块该留着
        let visibleRowCount = min(rows.count, limit)
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

    /// 键盘可达：维度分段可聚焦（行本身是只读文本，不做点击）
    var focusableRows: [MenuPanelRow] { dimSegment.focusableRows }

#if DEBUG
    /// 快照自证：直接切维度（不回调，避免取证过程触发整页刷新）
    func setDimensionForSnapshot(_ dimension: TokenDistroDimension) {
        self.dimension = dimension
    }

    /// 快照自证：顶部分段 / 占比条 / 8 行分布行
    var segmentForSnapshot: TokenSegmentedControl { dimSegment }
    var barForSnapshot: TokenStackBarView { bar }
    var rowsForSnapshot: [TokenRankingRowView] { rowViews }

    /// 快照自证：可见行数 / 实测行高 / 剩余留白（台账「行高 / 内容占比 / 空白」用）
    func rowMetricsForSnapshot() -> (visible: Int, rowHeight: CGFloat, blank: CGFloat) {
        layoutSubtreeIfNeeded()
        let visible = rowViews.filter { !$0.isHidden }.count
        // 行高扣掉行间距：rowsStack 高 ÷ 行数会把 2pt 间距也算进去
        let spacingTotal = CGFloat(max(0, visible - 1)) * rowsStack.spacing
        let height = visible > 0 ? (rowsStack.bounds.height - spacingTotal) / CGFloat(visible) : 0
        return (visible, height, spacer.bounds.height)
    }

    /// 快照自证：卡内各块实测高度（行高自适应的输入，用来查「谁把空间吸走了」）
    func cardPartsForSnapshot() -> String {
        layoutSubtreeIfNeeded()
        let parts = card.body.arrangedSubviews.filter { !$0.isHidden }.map { view -> String in
            let name: String
            if view === rowsStack { name = "rows" }
            else if view === spacer { name = "blank" }
            else if view === summaryGrid { name = "summary" }
            else if view === noteView { name = "note" }
            else if view === head { name = "head" }
            else if view === bar { name = "bar" }
            else { name = "dim" }
            return name + "=" + String(format: "%.1f", view.frame.height)
        }
        return "body=" + String(format: "%.1f", card.body.bounds.height) + " " + parts.joined(separator: " ")
    }
#endif
}
