import AppKit
import NetworkMonitorCore

// MARK: - 清理历史数据的范围选择与二次确认

/// 「清理历史数据」的两步交互：**选范围（带实时条数）→ 按规模二次确认**
///
/// 为什么单独成一个类型而不是塞进 SettingsTokenPane 的扩展：
/// 1. 这两步是一组内聚的交互规则（选项、默认值、文案口径），与页面布局无关；
/// 2. 同族文件合计门禁按 `<类名>+<职责>.swift` 聚合行数，塞进 pane 的扩展会直接顶破基线。
///
/// 口径要求（验收点）：
/// - 四个范围来自 `HarnessPurgeRange`（唯一数据源），弹窗里**不写死**天数；
/// - 条数必须**先查再确认**：范围切换时实时刷新「将删除 N 条事件」；
/// - 二次确认文案写清「范围 + 条数 + 会话文件不受影响 + 清完立即重扫」。
@MainActor
enum SettingsTokenPurgePrompt {

    /// 第一步：选范围，并实时显示该范围将删除多少条事件
    ///
    /// - Parameter preview: 范围 → 将删除的条数（负数 = 查不到，按「规模未知」展示）
    /// - Returns: 选定的范围；用户取消返回 nil
    static func askRange(preview: @escaping (HarnessRebuildScope) -> Int) -> HarnessPurgeRange? {
        let alert = NSAlert()
        alert.messageText = "清理哪些历史数据？"
        alert.informativeText = "只清理本机索引（事件与扫描记录在同一事务里删除），"
            + "DSH 会话文件本身不会被修改。清理后会自动重新扫描。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.setAccessibilityLabel("继续，进入清理确认")
        alert.buttons.last?.setAccessibilityLabel("取消，不清理")

        let accessory = RangeAccessoryView(preview: preview)
        alert.accessoryView = accessory
        accessory.refresh()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return accessory.selectedRange
    }

    /// 两步合成一次「确认 → 返回执行计划」：调用方只拿到「用户点过确认」的范围与条数
    ///
    /// 条数在读第二个弹窗前**再查一次**：用户可能在下拉里停留很久，
    /// 期间后台索引仍在写入，用第一次读到的数字确认会与实际删除量不符。
    struct Plan {
        let range: HarnessPurgeRange
        let eventCount: Int
        var scope: HarnessRebuildScope { range.scope }
        var title: String { range.title }
    }

    static func plan(preview: @escaping (HarnessRebuildScope) -> Int,
                     directoryPath: String) -> Plan? {
        guard let range = askRange(preview: preview) else { return nil }
        let eventCount = preview(range.scope)
        guard confirm(range: range, eventCount: eventCount, directoryPath: directoryPath) else { return nil }
        return Plan(range: range, eventCount: eventCount)
    }

    /// 第二步：写清规模的二次确认（不可撤销的操作必须先让用户看到代价）
    static func confirm(range: HarnessPurgeRange, eventCount: Int, directoryPath: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "确认清理" + range.confirmationText + "？"
        // 文案不要用 Markdown 强调（NSAlert.informativeText 是纯文本，星号会原样显示），
        // 规模靠换行独立成句来突出
        alert.informativeText = "将删除 " + eventCountText(eventCount) + "，"
            + "并同时删除对应的扫描记录，随后从会话文件重新扫描。\n\n"
            + "会话文件不受影响，但此操作不可撤销。"
            + (directoryPath.isEmpty ? "" : "\n\n数据目录：" + directoryPath)
        alert.alertStyle = .critical
        alert.addButton(withTitle: "清理 " + (eventCount > 0 ? String(eventCount) + " 条" : ""))
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.keyEquivalent = ""
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.setAccessibilityLabel("确认清理" + range.confirmationText)
        alert.buttons.last?.setAccessibilityLabel("取消，不清理")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 条数文案（负数 / 未知时说「规模未知」，绝不显示假的 0）
    static func eventCountText(_ count: Int) -> String {
        count >= 0 ? String(count) + " 条事件" : "规模未知的事件"
    }
}

// MARK: - 范围选择控件

/// 范围下拉 + 实时条数说明（NSAlert 的 accessoryView）
private final class RangeAccessoryView: NSView {

    private let preview: (HarnessRebuildScope) -> Int
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let countLabel = NSTextField(labelWithString: "")

    init(preview: @escaping (HarnessRebuildScope) -> Int) {
        self.preview = preview
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 52))

        popup.addItems(withTitles: HarnessPurgeRange.allCases.map(\.title))
        popup.selectItem(at: HarnessPurgeRange.allCases.firstIndex(of: .defaultRange) ?? 0)
        popup.target = self
        popup.action = #selector(selectionChanged)
        popup.setAccessibilityLabel("清理范围")
        popup.heightAnchor.constraint(equalToConstant: 22).isActive = true

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [popup, countLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            popup.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 当前选中的范围
    var selectedRange: HarnessPurgeRange {
        let index = popup.indexOfSelectedItem
        guard index >= 0, index < HarnessPurgeRange.allCases.count else { return .defaultRange }
        return HarnessPurgeRange.allCases[index]
    }

    @objc private func selectionChanged() {
        refresh()
    }

    /// 刷新条数说明（选中范围决定文案与颜色）
    func refresh() {
        let range = selectedRange
        let count = preview(range.scope)
        let text = count >= 0
            ? "将删除 " + String(count) + " 条事件（" + range.confirmationText + "）"
            : "将删除的规模未知（" + range.confirmationText + "）"
        countLabel.stringValue = text
        countLabel.setAccessibilityLabel(text)
        // 条数为 0 时明确说出来：否则用户会以为「点了没反应」
        countLabel.textColor = count == 0 ? .tertiaryLabelColor : .secondaryLabelColor
    }
}
