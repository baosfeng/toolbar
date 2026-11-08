import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 排行屏

/// 排行屏：维度分段（项目 / 模型）+ 占比条 + Top 8 两行式行 + 计数统计
///
/// 块顺序与 TokenScreen.blocks(for: .ranking) 一致。卡片高度撑到页脚上方（cardHeight），
/// 可见行由 rowsStack 按 fillEqually 均分 → 4 行时行距舒展、8 行时收紧也不压行；
/// 改前是单行截断式（名称被截成「deepseek-v4.1-f…」）+ 一条被截断的三项图例，都已删除。
@MainActor
final class TokenRankingScreenView: NSStackView {

    /// 当前维度（项目 / 模型）
    private(set) var dimension: TokenDistroDimension = .projects
    /// 维度切换回调：由 TokenPaneView 接到同一条 render 路径（不各走一套刷新）
    var onDimensionChange: (() -> Void)?

    /// Top 行数（屏内可见 8 行）
    static let topRowCount = 8

    private let dimSegment = TokenSegmentedControl(titles: ["项目", "模型"], expands: true)
    private let card = TokenBoxView(spacing: 3)
    private let head = TokenCardHead(title: TokenDistroDimension.projects.title)
    private let bar = TokenStackBarView(height: 8)
    /// 行容器：可见行均分剩余高度（弹性行高）
    private let rowsStack = NSStackView()
    private let rowViews = (0..<TokenRankingScreenView.topRowCount).map { _ in TokenRankingRowView() }
    private let emptyRow = TokenKeyRowView()
    private let statRows = (0..<2).map { _ in TokenKeyRowView() }

    init(cardHeight: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = PaneCardStyle.cardSpacing
        setAccessibilityRole(.group)
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
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 2
        // 吸收卡内剩余高度（其它行都是定高：分段 20 / 卡头 13 / 占比条 8 / 统计行）
        rowsStack.setContentHuggingPriority(.defaultLow, for: .vertical)
        for row in rowViews { rowsStack.addArrangedSubview(row) }
        for row in rowViews { row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true }

        dimSegment.heightAnchor.constraint(equalToConstant: 20).isActive = true
        dimSegment.setContentHuggingPriority(.required, for: .vertical)

        card.setRows([dimSegment, head, bar, rowsStack, emptyRow, TokenContentKit.twoColumn(statRows)])
        card.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
        addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    // MARK: 渲染

    /// 只搬运当前维度那一份分布行：颜色偏移与旧主面板一致（模型整体 +1 色）
    func update(model: TokenPaneModel) {
        let rows = dimension == .projects ? model.projects : model.models
        let copy = model.distroCopy
        let offset = dimension == .projects ? 0 : 1
        dimSegment.select(Self.index(for: dimension), notify: false)
        head.update(title: dimension.title, meta: copy.rangeTitle + " "
            + String(rows.count) + " 个")

        let barRows = Array(rows.prefix(TokenRankingScreenView.topRowCount))
        bar.update(shares: barRows.map { $0.share },
                   colors: barRows.map { TokenPaneStyle.distroColor($0.colorIndex + offset) },
                   accessibility: dimension.barAccessibility(range: model.range),
                   tip: TokenDerive.stackBarTip(barRows, hiddenCount: rows.count - barRows.count))

        for (index, view) in rowViews.enumerated() {
            if index < rows.count {
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

        let stats: [(String, String)] = dimension == .projects
            ? [("有记录项目", String(model.projectCount) + " 个"),
               ("会话数合计", String(rows.reduce(0) { $0 + $1.sessionCount }))]
            : [("有记录模型", String(model.modelCount) + " 个"),
               ("占比分母", "该范围全部模型合计")]
        for (index, row) in statRows.enumerated() where index < stats.count {
            row.update(title: stats[index].0, value: stats[index].1)
        }
        setAccessibilityLabel(dimension.cardAccessibility(range: model.range))
    }

    // MARK: 辅助

    /// 维度 → 分段下标（分段只两段，顺序固定：项目 / 模型）
    static func index(for dimension: TokenDistroDimension) -> Int {
        dimension == .projects ? 0 : 1
    }

    static func dimension(forIndex index: Int) -> TokenDistroDimension {
        index == 0 ? .projects : .models
    }

    /// 键盘可达：维度分段可聚焦（行本身是只读文本）
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
#endif
}
