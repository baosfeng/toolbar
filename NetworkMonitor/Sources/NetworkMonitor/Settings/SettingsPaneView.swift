import AppKit
import NetworkMonitorUI

// MARK: - 设置页基类

/// 设置页基类 — 每页实现一个子类，负责构建本页内容并在窗口重新显示时刷新状态
///
/// 设计约定：
/// - 每页自己持有依赖并组装控件，窗口只负责容器与切换，不做任何业务判断
/// - `page` 是页内垂直栈（页头 + 卡片 + 说明），子类在 `buildContent()` 里往里加卡片
/// - `refresh()` 在「切到该页」与「窗口重新显示」时调用，用于同步外部状态（权限、设备清单、凭据）
class SettingsPaneView: NSView {

    /// 页内垂直栈（页头 + 卡片 + 页尾说明）
    let page: SettingsPageStack

    /// 系统权限就地简版的快照来源（组合根在构造后注入；nil = 本页不显示权限卡）
    ///
    /// 放在基类而不是各页各存一份：五类权限的就地入口与「系统权限」页读同一份快照，
    /// 各页自己再持一个字段只会多出五份初始化路径。
    /// 命名带 `Source` 是为了与各页自己的 `permissions` 依赖区分（剪贴板页直接持有协议）。
    var permissionSource: (any SystemPermissionProviding)?
    /// 跳「系统权限」页（组合根注入；nil = 就地卡不显示跳转按钮）
    var onOpenPermissions: (() -> Void)?

    init(section: SettingsSection) {
        page = SettingsPageStack(section: section)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leadingAnchor),
            page.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.topAnchor.constraint(equalTo: topAnchor),
            page.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 子类构建内容（init 时调用一次）
    func buildContent() {}

    /// 追加权限就地简版卡（组合根在注入快照之后调用；子类不必知道卡怎么建）
    ///
    /// 为什么放在基类：五个功能页都要「状态点 + 一行说明 + 跳本页」这一块，
    /// 各页各写一遍就是五份变体；这里只留一条装配路径。
    func attachPermissionEntryCard(kinds: [SystemPermissionKind],
                                   sectionTitle: String = "系统权限（简版）") {
        guard let permissionSource else { return }
        let card = SystemPermissionInPlaceCard(permissions: permissionSource, kinds: kinds)
        card.onOpenCenter = { [weak self] in self?.onOpenPermissions?() }
        card.attach(to: page, sectionTitle: sectionTitle)
    }

    /// 同步外部状态（切页 / 重新显示时调用）
    func refresh() {}
}
