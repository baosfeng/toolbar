import AppKit

// MARK: - 不可用页

/// 占位页 — 某一分类的依赖未就绪时显示说明，而不是让窗口打不开或崩溃
///
/// 现实场景：互传服务未启动（权限/端口占用）时打开设置，互传页没有 service 可用。
final class SettingsUnavailablePane: SettingsPaneView {

    private let message: String

    init(section: SettingsSection, message: String) {
        self.message = message
        super.init(section: section)
    }

    override func buildContent() {
        page.addNote(message)
    }
}
