#if DEBUG
import AppKit

// MARK: - 设置窗口快照（通用页：菜单栏告警卡）

/// 从 `SettingsSnapshot` 拆出的一页取证（守住单文件 15 KiB 门禁）
///
/// 为什么按卡片真实文档坐标滚、而不是猜偏移量：告警卡上方还有启动 / 额度 / 显示 /
/// 鼠标滚轮四张卡，行数会随功能增减变化，写死偏移量的取证图迟早拍到空白处。
extension SettingsSnapshot {

    /// 通用页滚动到「菜单栏告警」卡（在本页首屏之外）
    static func captureScrolledGeneral(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let view = settings.prepareForSnapshot(.general),
              let pane = settings.currentPaneForSnapshot as? SettingsGeneralPane else { return }
        let card = pane.alertCard.card
        let cardRect = card.convert(card.bounds, to: settings.contentContainer)
        let viewportHeight = settings.contentScroll.contentView.bounds.height
        let maxOffset = max(0, settings.contentContainer.bounds.height - viewportHeight)
        let target = min(max(0, cardRect.minY - SettingsTheme.contentInset), maxOffset)
        settings.contentScroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        settings.contentScroll.reflectScrolledClipView(settings.contentScroll.contentView)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-general-alerts-\(suffix).png")
            MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }
}
#endif
