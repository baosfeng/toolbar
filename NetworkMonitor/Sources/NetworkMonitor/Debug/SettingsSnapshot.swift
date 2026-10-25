#if DEBUG
import AppKit

// MARK: - 设置窗口快照（仅 DEBUG）

/// 设置窗口六页 × 深浅色离屏渲染 — 复用菜单面板同一套渲染通道
///
/// 触发方式与菜单面板一致：`NM_SNAPSHOT_DIR=/tmp/nm-shots <可执行>`，
/// 产出 `settings-<分类>-{light,dark}.png`（760×540，与原型画布一致）。
@MainActor
enum SettingsSnapshot {

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
    }
}
#endif
