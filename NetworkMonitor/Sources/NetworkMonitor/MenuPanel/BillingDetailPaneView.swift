import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorFeatureBilling
import NetworkMonitorUI

// MARK: - 额度二级页（面板内覆盖式）

/// 单家 provider 的完整用量 —— 覆盖在主表之上，不新开窗口、不加 tab
///
/// 与系统页 SystemDetailPaneView 同一范式：onBack 回主表、内容纵向排、
/// 面板已有 NSScrollView 负责滚动（内容高过 520pt 就滚，不压缩任何一块）。
///
/// 内容四块（原型 F1 的覆盖页）：
/// 1. 窗口大卡：19pt 百分比 + 3pt 条 + 重置时间（与主表同一套 BillingWindowColumnView，只是大字号档）；
/// 2. 近 7 天柱图：该 provider 自己的用量（不跟页级分段，二级页固定 7 天）；
/// 3. 按模型明细：Top N 分布条 + 数值 + 占比；
/// 4. 纯余额型：余额大字 + 币种 + 说明行。
@MainActor
final class BillingDetailPaneView: NSView {

    /// 点「返回额度」回到主表
    var onBack: (() -> Void)?
    /// 错误条「重试」（由 BillingPaneView 转到 onRetry）
    var onRetry: (() -> Void)?

    // 以下成员放宽为 internal：+Sections 的数据扩展跨文件读写它们（同模块内无其它调用方）
    private let backButton = BillingDetailBackButton()
    let titleLabel = MenuPanelLabel.text("", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.primaryText)
    let metaLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)

    let windowCard = PaneCardBackgroundView()
    private let windowRow = NSStackView()
    var windowColumns: [BillingWindowColumnView] = []

    let balanceCard = PaneCardBackgroundView()
    let balanceLabel = MenuPanelLabel.text("", font: PaneCardStyle.heroFont,
                                                   color: PaneCardStyle.primaryText)
    let balanceUnit = MenuPanelLabel.text("", font: PaneCardStyle.heroUnitFont,
                                                  color: PaneCardStyle.tertiaryText)
    let balanceNote = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                  color: PaneCardStyle.tertiaryText)

    let chartCard = PaneCardBackgroundView()
    let chartTitle = MenuPanelLabel.text("", font: PaneCardStyle.cardTitleFont,
                                                 color: PaneCardStyle.primaryText)
    let chartMeta = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)
    let barsView = BillingChartBarsView()

    let modelCard = PaneCardBackgroundView()
    let modelList = BillingModelShareListView()

    let errorBanner = BillingErrorBannerView()
    let hintLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                                color: PaneCardStyle.tertiaryText)

    /// 柱图高度（二级页比主表高：44pt 与 Token 展开区主图同档）
    static let barHeight: CGFloat = PaneCardStyle.bucketChartHeight * 2

    private lazy var backRow: MenuPanelRow = {
        let row = MenuPanelRow(height: 20) { [weak self] in self?.onBack?() }
        row.contentStack.addArrangedSubview(backButton)
        row.setAccessibilityLabel("返回额度主表")
        return row
    }()

    var providerID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.group)
        setAccessibilityLabel("额度二级详情页")

        backButton.target = self
        backButton.action = #selector(handleBack)
        errorBanner.onRetry = { [weak self] in self?.onRetry?() }
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)

        let headBar = NSStackView(views: [backRow, titleLabel, MenuPanelLabel.spacer(), metaLabel])
        headBar.orientation = .horizontal
        headBar.alignment = .centerY
        headBar.spacing = 5

        windowColumns = (0..<BillingAggregate.maxColumns).map { _ in
            let column = BillingWindowColumnView()
            column.isDetail = true
            return column
        }
        windowRow.orientation = .horizontal
        windowRow.alignment = .top
        windowRow.distribution = .fillEqually
        windowRow.spacing = 6
        for column in windowColumns { windowRow.addArrangedSubview(column) }
        let windowBody = NSStackView(views: [windowRow])
        windowBody.orientation = .vertical
        windowBody.alignment = .leading
        windowBody.translatesAutoresizingMaskIntoConstraints = false
        windowCard.translatesAutoresizingMaskIntoConstraints = false
        windowCard.addSubview(windowBody)
        NSLayoutConstraint.activate([
            windowBody.leadingAnchor.constraint(equalTo: windowCard.contentView.leadingAnchor),
            windowBody.trailingAnchor.constraint(equalTo: windowCard.contentView.trailingAnchor),
            windowBody.topAnchor.constraint(equalTo: windowCard.contentView.topAnchor),
            windowBody.bottomAnchor.constraint(equalTo: windowCard.contentView.bottomAnchor),
            windowRow.widthAnchor.constraint(equalTo: windowBody.widthAnchor),
        ])

        balanceLabel.setContentHuggingPriority(.required, for: .horizontal)
        let balanceTitleRow = NSStackView(views: [balanceLabel, balanceUnit, MenuPanelLabel.spacer()])
        balanceTitleRow.orientation = .horizontal
        balanceTitleRow.alignment = .lastBaseline
        balanceTitleRow.spacing = PaneValueFormatting.gap
        let balanceBody = NSStackView(views: [balanceTitleRow, balanceNote])
        balanceBody.orientation = .vertical
        balanceBody.alignment = .leading
        balanceBody.spacing = 2
        balanceBody.translatesAutoresizingMaskIntoConstraints = false
        balanceCard.translatesAutoresizingMaskIntoConstraints = false
        balanceCard.addSubview(balanceBody)
        NSLayoutConstraint.activate([
            balanceBody.leadingAnchor.constraint(equalTo: balanceCard.contentView.leadingAnchor),
            balanceBody.trailingAnchor.constraint(equalTo: balanceCard.contentView.trailingAnchor),
            balanceBody.topAnchor.constraint(equalTo: balanceCard.contentView.topAnchor),
            balanceBody.bottomAnchor.constraint(equalTo: balanceCard.contentView.bottomAnchor),
            balanceTitleRow.widthAnchor.constraint(equalTo: balanceBody.widthAnchor),
            balanceNote.widthAnchor.constraint(equalTo: balanceBody.widthAnchor),
        ])

        barsView.heightAnchor.constraint(equalToConstant: Self.barHeight).isActive = true
        let chartHead = NSStackView(views: [chartTitle, MenuPanelLabel.spacer(), chartMeta])
        chartHead.orientation = .horizontal
        chartHead.alignment = .firstBaseline
        chartHead.spacing = 5
        let chartBody = NSStackView(views: [chartHead, barsView])
        chartBody.orientation = .vertical
        chartBody.alignment = .leading
        chartBody.spacing = 3
        chartBody.translatesAutoresizingMaskIntoConstraints = false
        chartCard.translatesAutoresizingMaskIntoConstraints = false
        chartCard.addSubview(chartBody)
        NSLayoutConstraint.activate([
            chartBody.leadingAnchor.constraint(equalTo: chartCard.contentView.leadingAnchor),
            chartBody.trailingAnchor.constraint(equalTo: chartCard.contentView.trailingAnchor),
            chartBody.topAnchor.constraint(equalTo: chartCard.contentView.topAnchor),
            chartBody.bottomAnchor.constraint(equalTo: chartCard.contentView.bottomAnchor),
        ])
        for view in chartBody.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: chartBody.widthAnchor).isActive = true
        }

        modelList.translatesAutoresizingMaskIntoConstraints = false
        modelCard.translatesAutoresizingMaskIntoConstraints = false
        modelCard.addSubview(modelList)
        NSLayoutConstraint.activate([
            modelList.leadingAnchor.constraint(equalTo: modelCard.contentView.leadingAnchor),
            modelList.trailingAnchor.constraint(equalTo: modelCard.contentView.trailingAnchor),
            modelList.topAnchor.constraint(equalTo: modelCard.contentView.topAnchor),
            modelList.bottomAnchor.constraint(equalTo: modelCard.contentView.bottomAnchor),
        ])

        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        hintLabel.preferredMaxLayoutWidth = MenuPanelStyle.contentWidth - PaneCardStyle.cardPaddingX * 2

        let root = NSStackView(views: [headBar, windowCard, balanceCard, chartCard,
                                       modelCard, errorBanner, hintLabel])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = PaneCardStyle.cardSpacing
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in root.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 覆盖页要有自己的底：主表在下面滚动时不会透出来
        PaneCardStyle.bandFill.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }

    @objc private func handleBack() { onBack?() }

    /// 键盘可达：只有返回按钮（内容全是自绘卡片，没有可聚焦行）
    var focusableRows: [MenuPanelRow] { [backRow] }
}
