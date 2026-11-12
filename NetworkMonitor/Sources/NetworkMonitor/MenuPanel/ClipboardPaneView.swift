import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板页

/// 剪贴板页 — 最近 5 条历史（点击即粘贴到目标 App）+ 空态 + 设置入口
///
/// 数据来自 `ClipboardRepository`（按时间倒序），刷新由 `AppEvents.clipboardChanged` 事件驱动；
/// 点击走与剪贴板面板一致的粘贴路径（`ClipboardPaster`），不做第二套实现。
final class ClipboardPaneView: MenuPanelPaneView {

    /// 最近条目条数上限
    private static let maxItems = 5

    /// 点击条目（由控制器触发粘贴）
    var onSelectItem: ((ClipboardItem) -> Void)?
    /// 点击「剪贴板设置…」
    var onRequestSettings: (() -> Void)?
    /// 点击表头（查看完整剪贴板历史面板）
    var onRequestHistory: (() -> Void)?

    /// 页头行 — 与其余四页同一件（22pt）
    private let headerView = PaneHeaderRowView(title: "剪贴板")
    /// 表头（「5 条 · 全部」可点开完整历史）：仍保留可点行，位置在页头之下
    private let header = MenuPanelHeaderRow(title: "最近复制", trailing: "0 条 · 全部")
    private let rowsStack = NSStackView()
    private let hintLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont, color: PaneCardStyle.secondaryText)
    private let emptyView = NSStackView()
    private let settingsRow: MenuPanelKeyValueRow
    /// 页脚状态带 — 与其余四页同壳（20pt）
    private let stateBand = PaneStateBandView()

    private var items: [ClipboardItem] = []
    private var itemRows: [MenuPanelClipboardRow] = []
    /// 条目签名 — 未变化时跳过重建
    private var itemsSignature = ""
    /// 提示自动隐藏任务
    private var hintTask: Task<Void, Never>?

    // MARK: - 初始化

    init() {
        settingsRow = MenuPanelKeyValueRow(symbol: "gearshape", title: "剪贴板设置…", value: "⌘,")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 0

        buildEmptyView()
        hintLabel.isHidden = true

        settingsRow.onClick = { [weak self] in self?.onRequestSettings?() }
        header.onClick = { [weak self] in self?.onRequestHistory?() }

        let stack = NSStackView(views: [headerView, header, rowsStack, hintLabel, emptyView,
                                        settingsRow, MenuPanelLabel.spacer(), stateBand])
        stack.orientation = .vertical
        stack.alignment = .leading
        // 主栈间距统一到令牌档（原 6pt 是这一页独有的取值）
        stack.spacing = PaneCardStyle.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for subview in stack.arrangedSubviews {
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        hintTask?.cancel()
    }

    /// 键盘可达行：表头（全部历史）→ 条目行 → 设置入口
    override var focusableRows: [MenuPanelRow] { [header] + itemRows + [settingsRow] }

    // MARK: - 空态

    /// 空态：一句话 + 轻量图形（SF Symbol，不用 emoji）
    private func buildEmptyView() {
        emptyView.orientation = .vertical
        emptyView.alignment = .centerX
        emptyView.spacing = 4

        if let icon = MenuPanelLabel.symbol("doc.on.clipboard", pointSize: 26, color: MenuPanelStyle.tertiaryText) {
            emptyView.addArrangedSubview(icon)
        }
        let title = MenuPanelLabel.text("还没有复制记录",
                                        font: PaneCardStyle.rowNameFont,
                                        color: PaneCardStyle.primaryText)
        title.alignment = .center
        title.heightAnchor.constraint(equalToConstant: 18).isActive = true
        emptyView.addArrangedSubview(title)
        let hint = MenuPanelLabel.text("复制任意内容后会出现在这里",
                                       font: PaneCardStyle.metaFont,
                                       color: PaneCardStyle.tertiaryText)
        hint.alignment = .center
        emptyView.addArrangedSubview(hint)
    }

    // MARK: - 数据更新

    /// 刷新条目列表（调用方已按时间倒序查询）
    func update(items newItems: [ClipboardItem]) {
        let limited = Array(newItems.prefix(Self.maxItems))
        let signature = limited.map { "\($0.id.uuidString):\($0.preview):\($0.kind.rawValue)" }
            .joined(separator: "|")
        items = limited
        header.updateTrailing(limited.isEmpty ? "0 条" : "\(limited.count) 条 · 全部")
        emptyView.isHidden = !limited.isEmpty
        rowsStack.isHidden = limited.isEmpty
        updateBand()

        guard signature != itemsSignature else { return }
        itemsSignature = signature

        for row in itemRows {
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        itemRows = limited.map { item in
            let row = MenuPanelClipboardRow(item: item)
            row.onClick = { [weak self] in self?.onSelectItem?(item) }
            return row
        }
        for row in itemRows {
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
    }

    /// 页脚状态带 — 条目数 / 上限 / 类型口径
    ///
    /// 只放本帧真实数据：没有条目时不写「0 条」冒充读数，直接让该项消失。
    private func updateBand() {
        let types = Set(items.map { MenuPanelClipboardRow.kindLabel(for: $0) })
        stateBand.update(items: [
            (key: "条目", value: items.isEmpty ? nil : "\(items.count) 条"),
            (key: "上限", value: "\(Self.maxItems) 条"),
            (key: "类型", value: types.isEmpty ? nil : types.sorted().joined(separator: " / ")),
        ])
    }

    /// 行内轻提示（粘贴降级原因等），1.6 秒后自动隐藏
    func showHint(_ message: String) {
        hintTask?.cancel()
        hintLabel.stringValue = message
        hintLabel.isHidden = message.isEmpty
        guard !message.isEmpty else { return }
        hintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.hintLabel.isHidden = true
        }
    }
}

// MARK: - 剪贴板条目行

/// 剪贴板条目行 — 相对时间（固定宽）+ 摘要（截断）+ 类型标签
final class MenuPanelClipboardRow: MenuPanelRow {

    private static let timeWidth: CGFloat = 56
    /// 正文用等宽字体（字号走令牌，五页同一档），便于对比代码片段
    private static let textFont: NSFont = PaneCardStyle.rowValueFont

    init(item: ClipboardItem) {
        super.init(height: MenuPanelStyle.rowHeight, onClick: {})

        let timeLabel = MenuPanelLabel.text(ClipboardRelativeTime.string(from: item.createdAt),
                                            font: PaneCardStyle.metaFont, color: PaneCardStyle.secondaryText)
        timeLabel.widthAnchor.constraint(equalToConstant: Self.timeWidth).isActive = true
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(timeLabel)

        let text = item.preview.isEmpty ? (item.text ?? "") : item.preview
        let textLabel = MenuPanelLabel.text(text, font: Self.textFont)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(textLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())

        let kindLabel = MenuPanelLabel.text(Self.kindLabel(for: item), font: PaneCardStyle.metaFont,
                                            color: PaneCardStyle.secondaryText)
        kindLabel.setContentHuggingPriority(.required, for: .horizontal)
        kindLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(kindLabel)

        setAccessibilityLabel("\(timeLabel.stringValue) \(text) \(kindLabel.stringValue)")
    }

    /// 类型标签：URL 文本显示为「链接」，其余按条目类型中文名
    ///
    /// 放宽为 internal：同文件的剪贴板页页脚状态带要用它统计类型分布。
    static func kindLabel(for item: ClipboardItem) -> String {
        if item.kind == .text {
            let text = item.text ?? item.preview
            if text.hasPrefix("http://") || text.hasPrefix("https://") { return "链接" }
        }
        switch item.kind {
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        case .rtf: return "富文本"
        }
    }
}
