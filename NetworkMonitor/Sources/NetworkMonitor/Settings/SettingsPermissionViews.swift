import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 权限行控件组合

/// 一行权限的控件组合 —— 灯 + 行尾标签 + 状态文案 + 主按钮 + 文字链 + 可选开关
///
/// 行本体仍是 `SettingsRowView`（左标题 / 副标题 + 右控件），这里把同一行的控件打包，
/// 避免用几并行数组维护（数量一旦对不上就会错位）。
struct PermissionRow {
    let row: SettingsRowView
    let dot: SettingsStatusDotView
    let tagLabel: PermissionTagLabel
    let stateLabel: NSTextField
    let primaryButton: NSButton
    let secondaryButton: NSButton
    let loginSwitch: NSSwitch
}

// MARK: - 行尾标签

/// 行尾小标签 —— bandFill 底 + 10pt 三级色（「需重启 / 无请求 API / 登录项」）
///
/// 不用 `NSTextField` 自带背景：那会把标签撑成系统输入框的样子；
/// 这里按文字实测宽画一块圆角底，与状态胶囊同族但更小一档。
final class PermissionTagLabel: NSView {

    private var text = ""
    private var widthConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
        let width = widthAnchor.constraint(equalToConstant: 0)
        widthConstraint = width
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 16),
            width,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 更新文案（nil / 空串 = 不显示）
    func update(_ text: String?) {
        let value = text ?? ""
        self.text = value
        isHidden = value.isEmpty
        widthConstraint?.constant = value.isEmpty ? 0 : Self.width(for: value)
        setAccessibilityLabel(value.isEmpty ? nil : value)
        needsDisplay = true
    }

    /// 宽度 = 左右内边距 + 文案实测宽
    static func width(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: SettingsTheme.noteFont]
        return 5 * 2 + ceil((text as NSString).size(withAttributes: attributes).width)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        SettingsTheme.drawStatusBand(in: bounds)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: SettingsTheme.noteFont,
            .foregroundColor: SettingsTheme.textTertiary,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

// MARK: - 多行说明

/// 可重写的页尾说明块 —— 条数随状态增减（全绿时不显示手动添加 / 重启提示）
///
/// 为什么不用 `SettingsPageStack.addNote`：那是构建期一次性追加的静态文案，
/// 状态变化后要能改写（用户勾完权限回来，提示必须当场消失）。
final class SettingsNoteListView: NSView {

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = SettingsTheme.noteGap
        stack.translatesAutoresizingMaskIntoConstraints = false
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

    /// 换掉全部说明（空串自动跳过，整块为空时不占位）
    func update(_ notes: [String]) {
        let visible = notes.filter { !$0.isEmpty }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for note in visible {
            let label = MenuPanelLabel.text(note, font: SettingsTheme.noteFont,
                                            color: SettingsTheme.textTertiary)
            label.maximumNumberOfLines = 3
            label.lineBreakMode = .byWordWrapping
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        isHidden = visible.isEmpty
        needsLayout = true
    }
}

// MARK: - 主按钮

/// 权限行的主按钮 —— 强调底（`accent`）与普通底（圆角描边）两档
///
/// 不用 `NSButton` 默认外观：定稿原型是 22pt 高、6pt 圆角、强调色实底，
/// 系统默认按钮的外观与主题角色对不上（换主题后按钮还是系统蓝）。
@MainActor
enum PermissionActionButton {

    /// 造一个主按钮（`primary` = 强调底）
    ///
    /// 强调底自己画：`bezelColor` 在非 key 窗口 / 中性外观下会被系统忽略
    /// （实测渲染成浅灰底，白字压上去完全看不见），所以底走 layer、文字走 attributedTitle。
    static func make(title: String, primary: Bool,
                     target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.isBordered = !primary
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.font = SettingsTheme.rowTitleFont
        SettingsControlChrome.applyStandardHeight(to: button)
        setTitle(title, on: button, primary: primary)
        return button
    }

    /// 更新标题（同一颗按钮在不同状态下指向不同动作）
    static func setTitle(_ title: String, on button: NSButton, primary: Bool) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: SettingsTheme.rowTitleFont,
            .foregroundColor: primary ? NSColor.white : SettingsTheme.textPrimary,
        ])
        button.layer?.backgroundColor = primary ? SettingsTheme.accent.cgColor : NSColor.clear.cgColor
        button.setAccessibilityLabel(title)
    }
}
