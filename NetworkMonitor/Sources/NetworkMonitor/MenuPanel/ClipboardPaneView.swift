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

    private let header = MenuPanelHeaderRow(title: "最近复制", trailing: "0 条 · 全部")
    private let rowsStack = NSStackView()
    private let hintLabel = MenuPanelLabel.text("", font: MenuPanelStyle.smallValueFont, color: .secondaryLabelColor)
    private let emptyView = NSStackView()
    private let settingsRow: MenuPanelKeyValueRow

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

        let stack = NSStackView(views: [header, rowsStack, hintLabel, emptyView, settingsRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
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

        if let icon = MenuPanelLabel.symbol("doc.on.clipboard", pointSize: 26, color: .tertiaryLabelColor) {
            emptyView.addArrangedSubview(icon)
        }
        emptyView.addArrangedSubview(MenuPanelLabel.text("还没有复制记录", font: MenuPanelStyle.bodyFont))
        let hint = MenuPanelLabel.text("复制任意内容后会出现在这里", font: MenuPanelStyle.sectionFont,
                                       color: .secondaryLabelColor)
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
    /// 正文用等宽字体，便于对比代码片段
    private static let textFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    init(item: ClipboardItem) {
        super.init(height: MenuPanelStyle.rowHeight, onClick: {})

        let timeLabel = MenuPanelLabel.text(ClipboardRelativeTime.string(from: item.createdAt),
                                            font: MenuPanelStyle.sectionFont, color: .secondaryLabelColor)
        timeLabel.font = MenuPanelStyle.sectionFont
        timeLabel.widthAnchor.constraint(equalToConstant: Self.timeWidth).isActive = true
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(timeLabel)

        let text = item.preview.isEmpty ? (item.text ?? "") : item.preview
        let textLabel = MenuPanelLabel.text(text, font: Self.textFont)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentStack.addArrangedSubview(textLabel)
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())

        let kindLabel = MenuPanelLabel.text(Self.kindLabel(for: item), font: MenuPanelStyle.sectionFont,
                                            color: .secondaryLabelColor)
        kindLabel.font = MenuPanelStyle.sectionFont
        kindLabel.setContentHuggingPriority(.required, for: .horizontal)
        kindLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(kindLabel)

        setAccessibilityLabel("\(timeLabel.stringValue) \(text) \(kindLabel.stringValue)")
    }

    /// 类型标签：URL 文本显示为「链接」，其余按条目类型中文名
    private static func kindLabel(for item: ClipboardItem) -> String {
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
