import AppKit

// MARK: - 页脚状态带（五页共用语法）

/// 状态带 —— 底 / 高度 / 内边距全部走 `PaneBandChrome`，五页同一个壳
///
/// 承载「数量 / 最近刷新 / 单位 / 索引 / 口径」这类说明项。此前三个页面各写一份
/// （额度页 `PaneStateBandView`、Token 页 `TokenStateBandView`、系统页 `SystemStateBandView`），
/// 各自 7 / 8 内边距、0xEEEFF2 / 0xF0F0F4 底色、9–10.5pt 字号，切页时页脚底色与字号都能看出差别。
///
/// 更新语义（性能契约）：条目视图**复用**，值 / 键 / 语气色都没变化的条目一帧不动 AppKit。
/// 只有「可见条数变化」或「从自定义内容切回文本」时才重排 `arrangedSubviews`。
/// 旧实现每次 update 都 clear + 重建（每秒 5 项 × 3 视图 = 15 个新视图），会让 `NSStackView`
/// 的第一基线约束每帧重新入引擎，进而拖出整树 Auto Layout 与文本测量缓存比较（实测占主线程 13%）。
final class PaneStateBandView: NSView {

    /// 内容栈（子类 / 自定义内容页可直接追加视图）
    let contentStack = NSStackView()

    /// 复用的条目视图池（下标 = 本帧第几个可见条目）
    private var itemViews: [PaneStateBandItemView] = []
    /// 尾部弹性占位：条目区之后恒有一个，用来把内容压到左侧
    private let spacerView = MenuPanelLabel.spacer()
    /// 当前以「文本条目模式」呈现的条数；-1 = 自定义内容模式（下帧 update 强制重排）
    private var textItemCount = -1

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
        let visible = items.compactMap { item -> (key: String, value: String, tone: NSColor)? in
            guard let value = item.value, !value.isEmpty else { return nil }
            return (item.key, value, item.tone ?? PaneCardStyle.secondaryText)
        }
        ensureTextItems(count: visible.count)
        for (index, item) in visible.enumerated() {
            itemViews[index].apply(key: item.key, value: item.value, tone: item.tone)
        }
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
        // 自定义内容与文本池互斥：下次 update(items:) 必须重排，不能沿用旧排列
        textItemCount = -1
    }

    /// 保证 `arrangedSubviews` 恰好是「前 count 个条目 + 尾部占位」
    ///
    /// 只有条数变化时才真的重排：稳态下每帧只改 label 文本，不触碰视图树。
    private func ensureTextItems(count: Int) {
        guard textItemCount != count else { return }
        while itemViews.count < count {
            itemViews.append(PaneStateBandItemView(key: "", value: "", tone: PaneCardStyle.secondaryText))
        }
        clearContent()
        for index in 0..<count {
            contentStack.addArrangedSubview(itemViews[index])
        }
        // 多出来的池成员留在内存里，供条数回升时复用（不上屏、不参与布局）
        contentStack.addArrangedSubview(spacerView)
        textItemCount = count
    }

    private func clearContent() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

// MARK: - 状态带条目（键 + 值 + 值的语气色）

/// 一条状态带的「键 值」组合 —— 构造一次后长期复用
///
/// 外观与 `PaneBandChrome.makeItemView` 完全一致：键 10pt 等宽三级色、值 10.5pt 等宽粗体、
/// 两项按第一基线对齐、间距 `bandInnerSpacing`。差别只在「值和键没变就不碰 AppKit」，
/// 因此每秒刷新不会再触发文本测量缓存比较（实测旧实现该项占主线程 13.29%）。
final class PaneStateBandItemView: NSView {

    private let keyLabel: NSTextField
    private let valueLabel: NSTextField
    private let stack = NSStackView()
    private var currentKey: String
    private var currentValue: String
    private var currentTone: NSColor

    init(key: String, value: String, tone: NSColor) {
        keyLabel = MenuPanelLabel.text(key, font: PaneCardStyle.metaFont,
                                       color: PaneCardStyle.tertiaryText)
        valueLabel = MenuPanelLabel.text(value, font: PaneCardStyle.rowValueStrongFont,
                                         color: tone)
        currentKey = key
        currentValue = value
        currentTone = tone
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        // 保留第一基线对齐（与旧 makeItemView 一致）：只在首次布局求解一次，
        // 复用之后不再每秒重建约束，因此不再有基线 → 文本测量的热路径
        stack.alignment = .firstBaseline
        stack.spacing = PaneCardStyle.bandInnerSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(keyLabel)
        stack.addArrangedSubview(valueLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新内容；键 / 值 / 语气色三项都没变时直接返回，不产生任何 AppKit 调用
    func apply(key: String, value: String, tone: NSColor) {
        if key != currentKey {
            keyLabel.stringValue = key
            currentKey = key
        }
        if value != currentValue {
            valueLabel.stringValue = value
            currentValue = value
        }
        if !tone.isEqual(currentTone) {
            valueLabel.textColor = tone
            currentTone = tone
        }
    }
}
