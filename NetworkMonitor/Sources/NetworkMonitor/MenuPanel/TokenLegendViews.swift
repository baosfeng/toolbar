import AppKit

// MARK: - Token 图例（色块 / 行视图；从 TokenRowViews.swift 拆出：单文件体积门禁）

/// 图例项：色块 + 标题 + 数值
///
/// dashed = 画虚线色块（累计基准、对比态对照序列），此时 color 决定虚线颜色。
struct TokenLegendItem {
    let color: NSColor?
    let title: String
    let value: String
    let dashed: Bool
    /// 悬停文案（不带时退回「标题 + 数值」）
    ///
    /// 图例只有 296pt 可用宽，长模型名会被截成 "deepseek-v4.1-flash…"，
    /// 全名与金额只能靠悬停看到；文案由 Core 的 TokenDistroRow.tip 直接给。
    let tip: String

    init(color: NSColor?, title: String, value: String, dashed: Bool = false, tip: String = "") {
        self.color = color
        self.title = title
        self.value = value
        self.dashed = dashed
        self.tip = tip
    }
}

/// 图例行：色块 + 标题 + 数值
final class TokenLegendRowView: NSView {

    private let stack = NSStackView()
    /// 最近一次渲染的项（供 #if DEBUG 的快照自证读取）
    private var lastItems: [TokenLegendItem] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 13),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 项数完全由调用方给的 items 决定（对比态两项、堆叠态三条）——这里不写死数量
    func update(items: [TokenLegendItem]) {
        lastItems = items
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            let swatch = TokenSwatch(color: item.color, dashed: item.dashed)
            let titleLabel = MenuPanelLabel.text(item.title,
                                                 font: TokenPaneStyle.legendFont,
                                                 color: TokenPaneStyle.tertiaryText)
            stack.addArrangedSubview(swatch)
            stack.addArrangedSubview(titleLabel)
            // 悬停文案逐项挂在「色块 + 标题 + 数值」三件上：图例被截断时鼠标落到哪一段都能看全
            let tip = item.tip.isEmpty ? item.title + " " + item.value : item.tip
            swatch.toolTip = tip
            titleLabel.toolTip = tip
            if !item.value.isEmpty {
                let valueLabel = MenuPanelLabel.text(item.value,
                                                     font: TokenPaneStyle.legendValueFont,
                                                     color: TokenPaneStyle.secondaryText)
                valueLabel.toolTip = tip
                stack.addArrangedSubview(valueLabel)
            }
        }
        // 整行也给一份逐项拼接的文案：鼠标落在项与项之间的空隙时仍有说明
        let rowTip = items.map { item -> String in
            item.tip.isEmpty ? item.title + " " + item.value : item.tip
        }.joined(separator: "\n")
        toolTip = rowTip.isEmpty ? nil : rowTip
        setAccessibilityLabel(items.map { $0.title + " " + $0.value }.joined(separator: "，"))
    }

#if DEBUG
    /// 快照自证：当前图例项（标题 / 数值 / 是否虚线色块），用于核对「项数与数据一致」
    func itemsForSnapshot() -> [(title: String, value: String, dashed: Bool)] {
        lastItems.map { ($0.title, $0.value, $0.dashed) }
    }

    /// 快照自证：整行挂上去的悬停文案（逐项拼接）
    var toolTipForSnapshot: String { toolTip ?? "" }
#endif

}

/// 图例小色块（虚线态画成一条短划线）
final class TokenSwatch: NSView {

    private let color: NSColor?
    /// 虚线态（累计基准 / 对比态对照序列）
    private let dashed: Bool

    init(color: NSColor?, dashed: Bool = false) {
        self.color = color
        self.dashed = dashed || color == nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: self.dashed ? 9 : 6),
            heightAnchor.constraint(equalToConstant: self.dashed ? 1 : 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        // 虚线态：按给定色画短划线；没给色（累计基准）时退回 55% 三级的灰
        let ink = color ?? TokenPaneStyle.secondaryText.withAlphaComponent(0.55)
        if dashed {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.minX, y: bounds.midY))
            path.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
            path.lineWidth = 1.4
            path.setLineDash([2.4, 2], count: 2, phase: 0)
            ink.setStroke()
            path.stroke()
            return
        }
        ink.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
