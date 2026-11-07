#if DEBUG
import AppKit

// MARK: - 设置窗口快照（仅 DEBUG）

/// 设置窗口六页 × 深浅色离屏渲染 — 复用菜单面板同一套渲染通道
///
/// 触发方式与菜单面板一致：`NM_SNAPSHOT_DIR=/tmp/nm-shots <可执行>`，
/// 产出 `settings-<分类>-{light,dark}.png`（760×540，与原型画布一致）。
@MainActor
enum SettingsSnapshot {

    /// 首次打开取证：新建一个窗口，**不做任何显式布局**就渲染根视图
    ///
    /// 用户反馈「第一次进设置页中间有大片空白，再进一次就好了」，
    /// 差别就在这里——`capture` 那条路径会先 `layoutSubtreeIfNeeded()`。
    /// 这张图用来复现首次路径（每次快照都会重出，作为回归证据）。
    static func captureFirstOpen(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let fresh = settings.makeFreshForFirstOpenProbe() else { return }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-firstopen-general-\(suffix).png")
            MenuPanelSnapshot.render(view: fresh, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 渲染全部设置页
    static func capture(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        let size = SettingsStyle.windowSize
        for section in SettingsSection.allCases {
            guard let view = settings.prepareForSnapshot(section) else { continue }
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent(
                    "settings-\(section.fileSuffix)-\(suffix).png")
                MenuPanelSnapshot.render(view: view, size: size,
                                         appearanceName: appearance, to: url)
            }
        }
        // 首次打开路径（不做任何显式布局）：复现「第一次进设置页中间一大片空白」，
        // 每次快照都重出，作为该版式问题的回归证据
        captureFirstOpen(directory: directory, settings: settings)
    }
}
#endif
