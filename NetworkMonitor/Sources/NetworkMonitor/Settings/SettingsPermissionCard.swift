import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 系统权限卡

/// 系统权限卡 —— 三类权限各一行（灯 + 状态 + 授权 / 定位），卡头带「检测状态」、卡下带可重写说明
///
/// 独立成组件的理由：它不是剪贴板页的私有零件（截图引导与面板页脚读同一份快照），
/// 而「一行 = 一类权限 + 三个按钮 + 两句随状态变化的说明」本身就是一个完整单元。
/// 页面只调 `attach(to:)`，行数、顺序与显隐规则全在这里。
///
/// 口径：状态一律读 `permissions.snapshot`，订阅由权限链推送（应用激活 / 面板打开 /
/// 点「检测状态」都会推一次），所以用户从系统设置勾完切回来，灯当场变绿。
@MainActor
final class SystemPermissionCard {

    private let permissions: any SystemPermissionProviding
    private let logger: LoggingService

    /// 卡体（页面 addCard 用）
    private let card = SettingsCardView()
    /// 卡下说明块（条数随状态变化，整块重写）
    private let notes = SettingsNoteListView()
    /// 卡头「检测状态」
    private(set) lazy var recheckButton: NSButton = {
        SettingsLinkButton.make("检测状态", target: self, action: #selector(recheckPermissions))
    }()
    private var rows: [PermissionRow] = []
    /// 快照订阅 token（deinit 退订）
    private var observerToken: UUID?

    init(permissions: any SystemPermissionProviding,
         logger: LoggingService = AppContext.shared.logger) {
        self.permissions = permissions
        self.logger = logger
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

    /// 挂进设置页（分组标题「系统权限」+ 卡 + 卡下说明）
    func attach(to page: SettingsPageStack) {
        page.addCard(card, sectionTitle: "系统权限", trailingAccessory: recheckButton)
        page.addRow(notes)
        render(permissions.snapshot)
    }

    // MARK: 渲染

    /// 立即按当前快照重绘（页面 refresh() 也会调一次，保证切页即最新）
    func refresh() { render(permissions.snapshot) }

    /// 按快照重绘（由订阅推送触发，页面不必自己知道有哪些刷新时机）
    private func render(_ snapshot: SystemPermissionSnapshot) {
        for (index, kind) in SystemPermissionKind.allCases.enumerated() {
            guard rows.indices.contains(index) else { continue }
            render(rows[index], entry: snapshot.entry(for: kind))
        }
        notes.update(snapshot.notes(appPath: permissions.appPath))
    }

    /// 行构建 —— 顺序完全由 `SystemPermissionKind.allCases` 决定
    private func buildRows() {
        for (index, kind) in SystemPermissionKind.allCases.enumerated() {
            let row = SettingsRowView(title: kind.title, subtitle: kind.purpose)
            let dot = SettingsStatusDotView()
            let stateLabel = MenuPanelLabel.text("", font: SettingsTheme.rowTitleFont,
                                                 color: SettingsTheme.textSecondary)
            stateLabel.alignment = .right
            stateLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
            stateLabel.setContentHuggingPriority(.required, for: .horizontal)
            stateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            let actionButton = SettingsLinkButton.make("授权", target: self,
                                                       action: #selector(requestPermission(_:)))
            actionButton.tag = index
            let guideButton = SettingsLinkButton.make("在 Finder 中显示", target: self,
                                                      action: #selector(revealAppInFinder))
            [dot, stateLabel, guideButton, actionButton].forEach(row.trailingStack.addArrangedSubview)
            card.addRow(row)
            rows.append(PermissionRow(row: row, dot: dot, stateLabel: stateLabel,
                                      actionButton: actionButton, guideButton: guideButton))
        }
    }

    /// 单行呈现：灯色 / 状态文案 / 副标题 / 两个按钮的显隐与标题
    private func render(_ row: PermissionRow, entry: SystemPermissionEntry) {
        row.dot.setColor(SettingsTheme.statusDotColor(entry.tone))
        row.stateLabel.stringValue = entry.label
        row.stateLabel.textColor = SettingsTheme.textSecondary
        row.row.update(subtitle: entry.detail)
        SettingsLinkButton.setTitle(entry.actionTitle, on: row.actionButton, color: SettingsTheme.accent)
        row.actionButton.isHidden = !entry.showsGrantAction
        row.guideButton.isHidden = !entry.showsManualAddGuide
        row.row.setAccessibilityLabel("\(entry.title)，\(entry.label)")
    }

    // MARK: 动作

    /// 行内「授权」：请求该类权限（会登记进系统设置清单并弹一次系统提示）后由订阅推送重绘
    @objc private func requestPermission(_ sender: NSButton) {
        guard SystemPermissionKind.allCases.indices.contains(sender.tag) else { return }
        permissions.request(SystemPermissionKind.allCases[sender.tag])
    }

    /// 行内「在 Finder 中显示」：用户手动「+」添加时需要自己找到 .app，省掉翻目录
    @objc private func revealAppInFinder() {
        permissions.revealAppInFinder()
    }

    /// 卡头「检测状态」：立即重读三类权限
    @objc private func recheckPermissions() {
        let snapshot = permissions.refresh()
        logger.info("手动检测系统权限：\(snapshot.summaryLabel)")
    }
}
