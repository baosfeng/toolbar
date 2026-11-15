import AppKit
import NetworkMonitorUI

// MARK: - 权限行控件组合

/// 一行权限的控件组合 —— 灯 + 状态文案 + 「在 Finder 中显示」+ 授权按钮
///
/// 行本体仍是 `SettingsRowView`（左标题 / 副标题 + 右控件），这里把同一行的四个控件打包，
/// 避免用三个并行数组维护（数量一旦对不上就会错位）。
struct PermissionRow {
    let row: SettingsRowView
    let dot: SettingsStatusDotView
    let stateLabel: NSTextField
    let actionButton: NSButton
    let guideButton: NSButton
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