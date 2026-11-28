import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 新版本说明区

/// 发布说明区 —— 固定高度的内部滚动区，按条目分块展示
///
/// 为什么是「固定高度 + 内部滚动」而不是「随内容撑高」：关于页已经超过一屏，
/// 说明撑到几十行会把「会话」卡推到窗口外；把高度锁死、内容在内部滚，
/// 一张卡的高度就与说明长度无关了（与剪贴板面板详情区同一口径）。
///
/// 为什么不用一行截断 + tooltip（改前）：本仓发布说明动辄 40+ 条，
/// 压成一行既读不出条目，也看不出哪句是标题。
final class SettingsReleaseNotesView: NSView {

    /// 说明区高度（含内边距）：约 7 行 11pt 文案，超出即内部滚动
    static let contentHeight: CGFloat = 132

    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private let documentView = SettingsFlippedView()
    private let placeholderLabel = MenuPanelLabel.text("—", font: SettingsTheme.noteFont,
                                                       color: SettingsTheme.textTertiary)
    /// 说明区左侧留出的项目符号宽度
    private static let bulletIndent: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 4
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 8)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = documentView

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.contentHeight),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
        ])

        // 读屏按 group 上报：说明是一整块内容，逐行进无障碍树只会念得很碎
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("新版本说明")
        update(lines: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 灌入说明行（空数组 → 占位一行）
    ///
    /// - Parameter placeholder: 无说明时的占位文案（「已是最新」与「无说明」共用同一档口径）
    func update(lines: [ReleaseNoteLine], placeholder: String? = nil) {
        clearRows()
        let text = placeholder ?? "—"
        guard !lines.isEmpty else {
            placeholderLabel.stringValue = text
            placeholderLabel.isHidden = false
            scrollView.isHidden = true
            setAccessibilityValue(text)
            return
        }
        placeholderLabel.isHidden = true
        scrollView.isHidden = false
        for line in lines {
            let label = makeLabel(for: line)
            contentStack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: contentStack.widthAnchor,
                                         constant: -Self.bulletIndent).isActive = true
            label.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor,
                                           constant: Self.bulletIndent).isActive = true
        }
        // 滚动归零：换版本后不该停在上一份说明的滚动位置
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        setAccessibilityValue(lines.map(\.text).joined(separator: "；"))
    }

    // MARK: 私有

    private func clearRows() {
        for view in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    /// 一行 → 标签（标题加粗、条目带项目符号、正文次级色）
    private func makeLabel(for line: ReleaseNoteLine) -> NSTextField {
        let font = SettingsTheme.rowSubtitleFont
        let label: NSTextField
        switch line.style {
        case .heading:
            label = MenuPanelLabel.text(line.text, font: .systemFont(ofSize: 11.5, weight: .semibold),
                                        color: SettingsTheme.textPrimary)
        case .bullet:
            // 有序列表自带 "1. " 序号，再补一个 "•" 会变成「• 1. 修了窗口位置」
            let prefix = line.text.first?.isNumber == true ? "" : "• "
            label = MenuPanelLabel.text(prefix + line.text, font: font, color: SettingsTheme.textPrimary)
        case .paragraph:
            label = MenuPanelLabel.text(line.text, font: font, color: SettingsTheme.textSecondary)
        case .truncationNotice:
            label = MenuPanelLabel.text(line.text, font: SettingsTheme.noteFont,
                                        color: SettingsTheme.textTertiary)
        }
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}