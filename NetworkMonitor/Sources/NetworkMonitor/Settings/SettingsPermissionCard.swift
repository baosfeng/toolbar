import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 系统权限卡

/// 系统权限卡 —— 五类权限各一行（灯 + 标签 + 状态 + 主按钮 + 次按钮），卡头「检测状态」、卡下可重写说明
///
/// 独立成组件的理由：它不是某一页的私有零件（「系统权限」页与各功能页的就地简版读同一份快照），
/// 而「一行 = 一类权限 + 若干随状态变化的按钮 + 随状态变化的说明」本身就是一个完整单元。
/// 页面只调 `attach(to:)`，行数、顺序与显隐规则全在这里；文案一律来自 `SystemPermissionEntry`。
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
    /// 卡头右侧「检测于 HH:mm」
    private let checkedAtLabel = MenuPanelLabel.text("", font: SettingsTheme.noteFont,
                                                     color: SettingsTheme.textTertiary)
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
        let accessory = NSStackView(views: [checkedAtLabel, recheckButton])
        accessory.orientation = .horizontal
        accessory.alignment = .centerY
        accessory.spacing = 8
        page.addCard(card, sectionTitle: "系统权限", trailingAccessory: accessory)
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
        checkedAtLabel.stringValue = Self.checkedAtText()
        renderLoginItemSwitch(snapshot)
    }

    /// 单行呈现：灯色 / 标签 / 状态文案 / 副标题 / 主次按钮 / 开关
    private func render(_ row: PermissionRow, entry: SystemPermissionEntry) {
        row.dot.setColor(SettingsTheme.statusDotColor(entry.tone))
        row.stateLabel.stringValue = entry.label
        row.stateLabel.textColor = entry.tone == .ok ? SettingsTheme.okInk
            : entry.tone == .warn ? SettingsTheme.warnInk : SettingsTheme.textTertiary
        row.tagLabel.update(entry.tag)
        row.row.update(subtitle: entry.detail)

        if let action = entry.primaryAction {
            PermissionActionButton.setTitle(action.title, on: row.primaryButton, primary: action.isPrimary)
            row.primaryButton.isHidden = false
        } else {
            row.primaryButton.isHidden = true
        }
        if let action = entry.secondaryAction {
            SettingsLinkButton.setTitle(action.title, on: row.secondaryButton,
                                       color: SettingsTheme.textSecondary)
            row.secondaryButton.isHidden = false
        } else {
            row.secondaryButton.isHidden = true
        }
        row.loginSwitch.isHidden = !entry.showsLoginItemSwitch
        row.row.setAccessibilityLabel("\(entry.title)，\(entry.label)")
    }

    /// 登录项开关的勾选态 = 系统侧登记态（不是偏好键：注册失败回滚后两者会分叉）
    private func renderLoginItemSwitch(_ snapshot: SystemPermissionSnapshot) {
        guard let index = SystemPermissionKind.allCases.firstIndex(of: .loginItem),
              rows.indices.contains(index) else { return }
        let state = snapshot.state(for: .loginItem)
        rows[index].loginSwitch.state = state.isGranted ? .on : .off
        rows[index].loginSwitch.isEnabled = state != .checking
    }

    /// 卡头时间戳（检测于 HH:mm）：只有时间没有来源，用户不知道是「刚点的」还是「切页顺手刷的」
    private static func checkedAtText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "检测于 \(formatter.string(from: Date()))"
    }

    /// 行构建 —— 顺序完全由 `SystemPermissionKind.allCases` 决定
    private func buildRows() {
        for (index, kind) in SystemPermissionKind.allCases.enumerated() {
            let row = SettingsRowView(title: kind.title, subtitle: kind.purpose)
            row.subtitleAllowsTwoLines()
            let dot = SettingsStatusDotView()
            let tagLabel = PermissionTagLabel()
            let stateLabel = MenuPanelLabel.text("", font: SettingsTheme.rowValueFont,
                                                 color: SettingsTheme.textSecondary)
            stateLabel.alignment = .right
            stateLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            stateLabel.setContentHuggingPriority(.required, for: .horizontal)
            stateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            let primaryButton = PermissionActionButton.make(title: "授权", primary: true,
                                                            target: self,
                                                            action: #selector(performPrimaryAction(_:)))
            primaryButton.tag = index
            let secondaryButton = SettingsLinkButton.make("在 Finder 中显示", target: self,
                                                          action: #selector(performSecondaryAction(_:)),
                                                          color: SettingsTheme.textSecondary)
            secondaryButton.font = SettingsTheme.noteFont
            secondaryButton.tag = index
            let loginSwitch = NSSwitch()
            loginSwitch.target = self
            loginSwitch.action = #selector(loginItemToggled(_:))
            loginSwitch.tag = index
            loginSwitch.setAccessibilityLabel(kind.title)
            [tagLabel, stateLabel, secondaryButton, primaryButton, loginSwitch]
                .forEach(row.trailingStack.addArrangedSubview)
            card.addRow(row)
            rows.append(PermissionRow(row: row, dot: dot, tagLabel: tagLabel, stateLabel: stateLabel,
                                      primaryButton: primaryButton, secondaryButton: secondaryButton,
                                      loginSwitch: loginSwitch))
        }
    }

    // MARK: 动作

    /// 主按钮：按当前状态下该类的「主动作」分派（授权 / 打开系统设置 / 去登录项 / 重启应用）
    @objc private func performPrimaryAction(_ sender: NSButton) {
        guard SystemPermissionKind.allCases.indices.contains(sender.tag) else { return }
        let entry = permissions.snapshot.entry(for: SystemPermissionKind.allCases[sender.tag])
        guard let action = entry.primaryAction else { return }
        perform(action, kind: entry.kind)
    }

    /// 次按钮（「在 Finder 中显示」）
    @objc private func performSecondaryAction(_ sender: NSButton) {
        guard SystemPermissionKind.allCases.indices.contains(sender.tag) else { return }
        let entry = permissions.snapshot.entry(for: SystemPermissionKind.allCases[sender.tag])
        guard let action = entry.secondaryAction else { return }
        perform(action, kind: entry.kind)
    }

    /// 动作 → 权限协议（视图不碰系统 API、不拼深链）
    private func perform(_ action: SystemPermissionAction, kind: SystemPermissionKind) {
        switch action {
        case .grant:
            permissions.request(kind)
            logger.info("用户请求系统权限：\(kind.title)")
        case .openSettings, .openLoginItems:
            permissions.openSettings(for: kind)
        case .revealInFinder:
            permissions.revealAppInFinder()
        case .restartApp:
            permissions.restartApp()
        }
    }

    /// 登录项开关：写偏好 + 注册，失败由中心回滚并把原因带进副标题与卡下警示句
    @objc private func loginItemToggled(_ sender: NSSwitch) {
        let target = sender.state == .on
        if let reason = permissions.setLoginItemEnabled(target) {
            logger.warning("开机自启动未生效（已回滚）：\(reason)")
        }
        render(permissions.snapshot)
    }

    /// 卡头「检测状态」：置检测中 → 等通知授权异步回调回来填真值
    @objc private func recheckPermissions() {
        permissions.recheck()
        logger.info("手动检测系统权限（五类）")
    }
}
