import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 功能页的就地简版

/// 权限就地简版卡 —— 功能页只显示「状态点 + 一行说明 + 跳本页按钮」
///
/// 为什么保留它：用户在剪贴板页想确认 ⌘V 为什么没反应，不该先被赶去别的分类；
/// 但就地入口不再自带「授权 / 在 Finder 中显示 / 重启应用」那一整套动作 ——
/// 那些只在「系统权限」页存在，避免同一个动作在五个地方各写一遍文案。
@MainActor
final class SystemPermissionInPlaceCard {

    private let permissions: any SystemPermissionProviding
    private let kinds: [SystemPermissionKind]
    private let showsOpenCenterButton: Bool
    private let card = SettingsCardView()
    private var rows: [InPlaceRow] = []
    private var observerToken: UUID?
    /// 「查看系统权限」的跳转（由组合根注入；nil = 不显示按钮）
    var onOpenCenter: (() -> Void)?

    init(permissions: any SystemPermissionProviding,
         kinds: [SystemPermissionKind],
         showsOpenCenterButton: Bool = true) {
        self.permissions = permissions
        self.kinds = kinds
        self.showsOpenCenterButton = showsOpenCenterButton
        buildRows()
        observerToken = permissions.addObserver { [weak self] snapshot in
            self?.render(snapshot)
        }
    }

    isolated deinit {
        if let observerToken {
            permissions.removeObserver(observerToken)
        }
    }

    // MARK: 装配

    /// 挂进设置页（分组标题 + 简版卡）
    func attach(to page: SettingsPageStack, sectionTitle: String = "系统权限") {
        page.addCard(card, sectionTitle: sectionTitle)
        render(permissions.snapshot)
    }

    /// 按当前快照重绘
    func refresh() { render(permissions.snapshot) }

    // MARK: 渲染

    private func render(_ snapshot: SystemPermissionSnapshot) {
        for (index, kind) in kinds.enumerated() {
            guard rows.indices.contains(index) else { continue }
            let entry = snapshot.entry(for: kind)
            let row = rows[index]
            row.dot.setColor(SettingsTheme.statusDotColor(entry.tone))
            row.row.update(subtitle: entry.detail)
            row.stateLabel.stringValue = entry.inPlaceStateLabel
            row.stateLabel.textColor = entry.tone == .ok ? SettingsTheme.okInk
                : entry.tone == .warn ? SettingsTheme.warnInk : SettingsTheme.textTertiary
            row.openButton.isHidden = !showsOpenCenterButton || onOpenCenter == nil
        }
    }

    private func buildRows() {
        for kind in kinds {
            let row = SettingsRowView(title: kind.title, subtitle: kind.purpose)
            let dot = SettingsStatusDotView()
            let stateLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textSecondary)
            let openButton = SettingsLinkButton.make("查看系统权限", target: self,
                                                     action: #selector(openCenter))
            [dot, stateLabel, openButton].forEach(row.trailingStack.addArrangedSubview)
            card.addRow(row)
            rows.append(InPlaceRow(row: row, dot: dot, stateLabel: stateLabel, openButton: openButton))
        }
    }

    @objc private func openCenter() {
        onOpenCenter?()
    }
}

/// 简版行的控件组合
private struct InPlaceRow {
    let row: SettingsRowView
    let dot: SettingsStatusDotView
    let stateLabel: NSTextField
    let openButton: NSButton
}
