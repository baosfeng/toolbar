import AppKit

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

    /// 同步外部状态（切页 / 重新显示时调用）
    func refresh() {}
}
