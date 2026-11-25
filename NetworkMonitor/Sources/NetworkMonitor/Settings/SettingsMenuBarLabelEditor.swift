import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 菜单栏逐项自定义弹窗

/// 逐项自定义前缀弹窗 —— 17 项指标（磁盘 I/O 另有「写」片段）各一行输入框
///
/// 为什么用弹窗而不是行内 17 个输入框：设置页一行 32pt，17 项摊进卡片会多出 550pt，
/// 把「显示方式」卡撑到一屏以上；而逐项自定义是低频操作，改完即走。
/// 与 `SettingsProvidersPane+Instances` 的新增 / 重命名同一交互范式（`NSAlert` + 输入）。
///
/// 保存语义：**只写改动过的项**——输入框留空表示「这一项回到档位默认」，
/// 所以空值会被显式删掉；没改的项不碰（避免把用户上次填的值抹成默认）。
@MainActor
final class SettingsMenuBarLabelEditor {

    private let preferences: MenuBarDisplayPreferences
    private let onSave: () -> Void
    /// key → 输入框（key = metric rawValue；磁盘 I/O 的写片段用
    /// `MenuBarLabelResolver.diskWriteKey`）
    private var fields: [String: NSTextField] = [:]

    init(preferences: MenuBarDisplayPreferences, onSave: @escaping () -> Void) {
        self.preferences = preferences
        self.onSave = onSave
    }

    /// 弹出编辑窗并以**表单**方式挂在设置窗口上（模态会冻住设置页的重绘）
    ///
    /// 没有宿主窗口时（快照 / 离屏）直接退化成 `runModal`，行为一致。
    /// - Parameter sheetParent: 设置窗口；nil = 独立模态
    func present(sheetParent: NSWindow?) {
        fields.removeAll()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "逐项自定义菜单栏前缀"
        alert.informativeText = "留空 = 跟随上面的「标签」档；灰色字是该项的默认写法。"
            + "改哪一项就只影响哪一项，重启后保留。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.accessoryView = makeAccessory()

        guard let sheetParent else {
            if alert.runModal() == .alertFirstButtonReturn { save() }
            return
        }
        alert.beginSheetModal(for: sheetParent) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.save()
        }
    }

    // MARK: - 构建

    /// 滚动容器：18 行 × 26pt ≈ 470pt，直接摊开会顶出屏幕，固定 300pt 高度内滚动
    private func makeAccessory() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        for metric in MenuBarMetric.defaultOrder {
            stack.addArrangedSubview(makeRow(
                title: metric.displayName,
                key: metric.rawValue,
                fallback: MenuBarLabelResolver.primaryLabel(for: metric,
                                                            style: preferences.labelStyle,
                                                            customLabels: [:]),
                current: preferences.customLabel(for: metric)))
        }
        stack.addArrangedSubview(makeRow(
            title: "磁盘 I/O · 写",
            key: MenuBarLabelResolver.diskWriteKey,
            fallback: MenuBarLabelResolver.secondaryLabel(for: .diskIO,
                                                          style: preferences.labelStyle,
                                                          customLabels: [:]) ?? "W ",
            current: preferences.diskWriteLabel))

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -4),
            document.widthAnchor.constraint(equalToConstant: 372),
        ])
        scroll.documentView = document
        return scroll
    }

    private func makeRow(title: String, key: String, fallback: String, current: String) -> NSView {
        let label = MenuPanelLabel.text(title, font: SettingsTheme.rowValueFont,
                                        color: SettingsTheme.textPrimary)
        label.widthAnchor.constraint(equalToConstant: 108).isActive = true
        let field = NSTextField(frame: .zero)
        field.stringValue = current
        // 占位写默认值：用户一眼看出「不填会长成什么样」
        field.placeholderString = fallback.trimmingCharacters(in: .whitespaces)
        field.font = SettingsTheme.rowValueFont
        field.setAccessibilityLabel(title + "前缀")
        fields[key] = field
        let row = NSStackView(views: [label, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        field.widthAnchor.constraint(equalToConstant: 232).isActive = true
        return row
    }

    // MARK: - 保存

    private func save() {
        for (key, field) in fields {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = key == MenuBarLabelResolver.diskWriteKey
                ? preferences.diskWriteLabel
                : (preferences.customLabels[key] ?? "")
            guard text != original else { continue }
            if key == MenuBarLabelResolver.diskWriteKey {
                preferences.setDiskWriteLabel(text)
            } else if let metric = MenuBarMetric(rawValue: key) {
                preferences.setCustomLabel(text, for: metric)
            }
        }
        onSave()
    }
}
