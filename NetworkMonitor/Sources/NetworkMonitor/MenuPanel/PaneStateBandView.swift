import AppKit

// MARK: - 页脚状态带（五页共用语法）

/// 状态带 —— 底 / 高度 / 内边距全部走 `PaneBandChrome`，五页同一个壳
///
/// 承载「数量 / 最近刷新 / 单位 / 索引 / 口径」这类说明项。此前三个页面各写一份
/// （额度页 `PaneStateBandView`、Token 页 `TokenStateBandView`、系统页 `SystemStateBandView`），
/// 各自 7 / 8 内边距、0xEEEFF2 / 0xF0F0F4 底色、9–10.5pt 字号，切页时页脚底色与字号都能看出差别。
final class PaneStateBandView: NSView {

    /// 内容栈（子类 / 自定义内容页可直接追加视图）
    let contentStack = NSStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = PaneCardStyle.bandGroupSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        PaneBandChrome.constrain(contentStack, in: self)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        PaneBandChrome.draw(in: bounds)
        super.draw(dirtyRect)
    }

    /// 更新键值对（值为 nil / 空串的项跳过）
    ///
    /// - Parameter tone: 值文字色；nil = 次级文字色（与旧调用点默认一致）
    func update(items: [(key: String, value: String?, tone: NSColor?)]) {
        clearContent()
        for item in items {
            guard let value = item.value, !value.isEmpty else { continue }
            contentStack.addArrangedSubview(PaneBandChrome.makeItemView(
                key: item.key, value: value, tone: item.tone ?? PaneCardStyle.secondaryText))
        }
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())
        setAccessibilityLabel(items.compactMap { item in
            item.value.map { "\(item.key) \($0)" }
        }.joined(separator: "，"))
    }

    /// 便利重载：不带语气色
    func update(items: [(key: String, value: String?)]) {
        update(items: items.map { (key: $0.key, value: $0.value, tone: nil) })
    }

    /// 自定义内容（系统页电池环 / 信号圆点这类非文本件）：调用方自己摆视图
    func setContentViews(_ views: [NSView]) {
        clearContent()
        for view in views {
            contentStack.addArrangedSubview(view)
        }
    }

    private func clearContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}
