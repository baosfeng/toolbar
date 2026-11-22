import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 余额型 provider 行（总表下段）

/// 余额型一行 —— 「图标 + 名称」左对齐，「金额大字 + 币种」右对齐
///
/// 与用量行同一张表，但语义不同：这三家没有窗口百分比（DeepSeek / Moonshot / OpenRouter），
/// 只有金额或「无限制」。原型把它们的金额放大到 15pt 贴右、币种跟在后面，
/// 一眼就能读出「还有多少钱」，而不是塞进百分比列里显示一个「—」。
@MainActor
final class BillingBalanceRowView: MenuPanelRow {

    /// 行高（原型实测：余额行 22pt；比用量行矮，因为它们只有一行内容）
    static let rowHeight: CGFloat = 22

    /// 点击进入二级页
    var onOpen: (() -> Void)?

    private let iconView: NSImageView?
    private let nameLabel = MenuPanelLabel.text("", font: PaneCardStyle.rowNameFont,
                                                 color: PaneCardStyle.primaryText)
    private let amountLabel = MenuPanelLabel.text("", font: BillingBalanceRowView.amountFont,
                                                  color: PaneCardStyle.primaryText)
    private let currencyLabel = MenuPanelLabel.text("", font: PaneCardStyle.cardValueUnitFont,
                                                    color: PaneCardStyle.tertiaryText)
    private(set) var providerID: String = ""

    /// 金额字号：15pt 粗等宽（比窗口百分比大一档，比 Hero 小一档）
    static let amountFont: NSFont = PaneCardStyle.cardValueCompactFont

    init() {
        iconView = MenuPanelLabel.symbol("dollarsign.circle", pointSize: 10, color: PaneCardStyle.accentText)
        super.init(height: Self.rowHeight, onClick: nil)

        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        currencyLabel.setContentHuggingPriority(.required, for: .horizontal)
        currencyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        amountLabel.alignment = .right
        currencyLabel.alignment = .right

        contentStack.spacing = 3
        if let iconView { contentStack.addArrangedSubview(iconView) }
        contentStack.addArrangedSubview(nameLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        contentStack.addArrangedSubview(amountLabel)
        contentStack.addArrangedSubview(currencyLabel)

        onClick = { [weak self] in self?.onOpen?() }
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 数据

    /// 更新一行
    ///
    /// - Parameters:
    ///   - id: 实例标识
    ///   - name: 展示名
    ///   - symbolName: 图标
    ///   - amount: 已格式化的金额（nil = 无限制，显示「无限制」）
    ///   - currency: 币种文案（「CNY」/「USD」；无限制时为空）
    func update(id: String, name: String, symbolName: String,
                amount: String?, currency: String?) {
        providerID = id
        nameLabel.stringValue = name
        nameLabel.toolTip = name
        if let iconView {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            iconView.contentTintColor = PaneCardStyle.accentText
        }
        let isUnlimited = amount == nil
        amountLabel.stringValue = amount ?? "无限制"
        amountLabel.font = isUnlimited ? Self.unlimitedFont : Self.amountFont
        amountLabel.textColor = isUnlimited ? PaneCardStyle.okInk : PaneCardStyle.primaryText
        currencyLabel.stringValue = currency ?? ""
        setAccessibilityLabel(Self.accessibilityText(name: name, amount: amount, currency: currency))
    }

    /// 「无限制」用小一号字：它不是数值，放大反而显得像金额
    static let unlimitedFont: NSFont = .systemFont(ofSize: 11, weight: .bold)

    static func accessibilityText(name: String, amount: String?, currency: String?) -> String {
        guard let amount else { return name + " 无限制" }
        let code = currency.map { " " + $0 } ?? ""
        return name + " 余额 " + amount + code
    }
}
