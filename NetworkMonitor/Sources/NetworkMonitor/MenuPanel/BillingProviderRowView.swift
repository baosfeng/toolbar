import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - provider 行（总表里的一行）

/// 总表一行 —— 左「图标 + 名称 + 状态胶囊」，右 N 个额度窗口列
///
/// 版式来自原型 F1：一行 34pt 读完一家（名称区固定 96pt，其余均分给窗口列）。
/// 行本身可点：进入该 provider 的覆盖式二级页（完整用量 + 重置窗口 + 模型明细），
/// 不再像旧版那样在卡内就地展开——展开会把下面几家的行全部推走。
///
/// 键盘可达：继承 `MenuPanelRow`，Tab 到它、Enter/空格进入二级页、读屏按 role=button。
@MainActor
final class BillingProviderRowView: MenuPanelRow {

    /// 名称区固定宽度（112pt：够放 «Open Design» + «home» 副标；再宽三列窗口会掉到 44pt）
    /// 名称区宽度 —— 随列数变化
    ///
    /// 两列时每列还有约 97pt，够放「每周 · 11/25 05:55」，名称给 96pt 就够；
    /// 三列时每列只剩约 52pt（只留窗口名），名称让到 112pt 才放得下「Open Design」加「home」副标。
    /// 名称与窗口列是零和的，固定一个值必然在其中一种列数下截断。
    static func nameColumnWidth(columnCount: Int) -> CGFloat {
        columnCount >= BillingAggregate.maxColumns ? 112 : 96
    }
    /// 行高（原型实测：用量行 34pt）
    static let rowHeight: CGFloat = 34
    /// 窗口列之间的间距
    private static let columnSpacing: CGFloat = 4

    /// 点击进入二级页
    var onOpen: (() -> Void)?

    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: BillingProviderRowView.nameFont,
                                                 color: PaneCardStyle.primaryText)
    /// 实例副标（同名多实例时区分，如 «home»；nil = 默认实例不显示）
    ///
    /// 挤在主名右侧同一行（9pt tertiary），不单独占一行——见 init 里的说明。
    private let subtitleLabel = MenuPanelLabel.text("", font: BillingProviderRowView.subtitleFont,
                                                     color: PaneCardStyle.tertiaryText)
    private let chip = BillingStatusChipView()
    private let columnsRow = NSStackView()
    /// 名称区宽度约束（列数变化时改 constant，不重建视图）
    private var nameWidthConstraint: NSLayoutConstraint?

    /// 复用的窗口列（最多 3 列，按需显隐；避免每次刷新重建视图）
    private var columns: [BillingWindowColumnView] = []
    private(set) var providerID: String = ""

    /// 名称字号（10.5pt 半粗，与行名同档）
    static let nameFont: NSFont = .systemFont(ofSize: 10.5, weight: .semibold)
    /// 实例副标字号（9pt，比主名低一档：它只用来区分同名实例）
    static let subtitleFont: NSFont = .systemFont(ofSize: 9, weight: .regular)

    init() {
        iconView = MenuPanelLabel.symbol("creditcard", pointSize: 10, color: PaneCardStyle.accentText)
        super.init(height: Self.rowHeight, onClick: nil)

        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 名称区：图标 + 一列两行（第一行「主名 + 实例副标同行」，第二行状态胶囊）
        //
        // 副标与主名同行而不是各占一行：各占一行时该行比其他 provider 高约 12pt，
        // 表格四行高度不齐，一列数字的基线也跟着错位。
        subtitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.font = Self.subtitleFont
        let titleRow = NSStackView(views: [nameLabel, subtitleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .lastBaseline
        titleRow.spacing = 3
        let nameStack = NSStackView(views: [titleRow, chip])
        nameStack.orientation = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2

        let nameArea = NSStackView()
        nameArea.orientation = .horizontal
        nameArea.alignment = .centerY
        nameArea.spacing = 3
        if let iconView { nameArea.addArrangedSubview(iconView) }
        nameArea.addArrangedSubview(nameStack)
        nameArea.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = nameArea.widthAnchor.constraint(
            equalToConstant: Self.nameColumnWidth(columnCount: BillingAggregate.maxColumns))
        widthConstraint.isActive = true
        nameWidthConstraint = widthConstraint
        nameStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        columnsRow.orientation = .horizontal
        columnsRow.alignment = .top
        columnsRow.distribution = .fillEqually
        columnsRow.spacing = Self.columnSpacing
        columns = (0..<BillingAggregate.maxColumns).map { _ in BillingWindowColumnView() }
        for column in columns {
            columnsRow.addArrangedSubview(column)
            column.isHidden = true
        }

        contentStack.spacing = 6
        contentStack.addArrangedSubview(nameArea)
        contentStack.addArrangedSubview(columnsRow)
        columnsRow.setContentHuggingPriority(.defaultLow, for: .horizontal)

        onClick = { [weak self] in self?.onOpen?() }
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据

    /// 更新一行
    ///
    /// - Parameters:
    ///   - row: 汇总后的行数据（窗口列已按全表列数对齐）
    ///   - symbolName: provider 图标（SF Symbol）
    ///   - statusKind: 状态胶囊语义档
    ///   - columnCount: 全表统一的列数
    func update(row: BillingAggregate.ProviderRow,
                symbolName: String,
                statusKind: BillingStatusKind,
                columnCount: Int) {
        providerID = row.id
        nameLabel.stringValue = row.name
        nameLabel.toolTip = row.subtitle.map { row.name + " (" + $0 + ")" } ?? row.name
        subtitleLabel.stringValue = row.subtitle ?? ""
        subtitleLabel.isHidden = (row.subtitle ?? "").isEmpty
        applyIcon(symbolName)
        chip.update(kind: Self.chipKind(statusKind), text: BillingProviderStatusLogic.text(statusKind))

        let showColumns = min(max(columnCount, 1), columns.count)
        let nameWidth = Self.nameColumnWidth(columnCount: showColumns)
        if nameWidthConstraint?.constant != nameWidth {
            nameWidthConstraint?.constant = nameWidth
            needsLayout = true
        }
        // 三列时每列约 59pt：重置行省掉「重置」二字才放得下窗口名与时分
        let compact = showColumns >= BillingAggregate.maxColumns
        let padded = BillingAggregate.padded(row, columnCount: showColumns)
        for (index, column) in columns.enumerated() {
            guard index < padded.count, let spec = padded[index] else {
                column.isHidden = true
                column.clear()
                continue
            }
            column.isHidden = false
            column.isCompact = compact
            column.update(BillingWindowColumnView.Spec(title: spec.title,
                                                       remaining: spec.remaining,
                                                       resetsAt: spec.resetsAt,
                                                       badge: spec.badge))
        }
        setAccessibilityLabel(Self.accessibilityText(row: row, status: statusKind))
        invalidateIntrinsicContentSize()
    }

    private func applyIcon(_ symbolName: String) {
        guard let iconView else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = PaneCardStyle.accentText
    }

    /// 语义档 -> 视图档（与旧卡头同一映射，集中在一处）
    static func chipKind(_ kind: BillingStatusKind) -> BillingStatusChipView.Kind {
        switch kind {
        case .ok: return .ok
        case .warn: return .warn
        case .error: return .error
        case .loading: return .loading
        case .idle: return .idle
        }
    }

    /// 读屏文案：名称 + 状态 + 各窗口剩余
    static func accessibilityText(row: BillingAggregate.ProviderRow,
                                  status: BillingStatusKind) -> String {
        var parts = [row.fullName, BillingProviderStatusLogic.text(status)]
        for window in row.windows {
            parts.append(window.title + " 剩余 " + formatPercent(window.remaining))
        }
        return parts.joined(separator: "，")
    }
}
