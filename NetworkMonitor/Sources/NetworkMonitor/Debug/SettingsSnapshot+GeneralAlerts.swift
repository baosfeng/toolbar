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
/// 通用页滚动到「菜单栏显示方式」卡（本轮新增：模板 / 密度 / 单位 / 标签 / 布局 + 逐项自定义）
    ///
    /// 为什么单独出这一张：本卡在本页首屏之外，且「标签」档位是用户口径
    /// 「直接展示 Token 等很大的标识，太浪费空间」的落点——
    /// 需要一张图能同时看到标签下拉、逐项自定义入口与相邻的密度/单位行。
    static func captureScrolledGeneralDisplayStyle(directory: URL, settings: SettingsWindow?) {
        guard let settings else { return }
        guard let view = settings.prepareForSnapshot(.general),
              let pane = settings.currentPaneForSnapshot as? SettingsGeneralPane else { return }
        let card = pane.displayStyleCard.card
        let cardRect = card.convert(card.bounds, to: settings.contentContainer)
        let viewportHeight = settings.contentScroll.contentView.bounds.height
        let maxOffset = max(0, settings.contentContainer.bounds.height - viewportHeight)
        let target = min(max(0, cardRect.minY - SettingsTheme.contentInset), maxOffset)
        settings.contentScroll.contentView.scroll(to: NSPoint(x: 0, y: target))
        settings.contentScroll.reflectScrolledClipView(settings.contentScroll.contentView)
        // 控件态（标签档 / 密度 / 单位 / 布局）离屏看不出来，与偏好真值并排落盘
        writeDisplayStyleControls(directory: directory, pane: pane)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let url = directory.appendingPathComponent("settings-general-display-style-\(suffix).png")
            MenuPanelSnapshot.render(view: view, size: SettingsStyle.windowSize,
                                     appearanceName: appearance, to: url)
        }
    }

    /// 显示方式卡的控件真值（离屏快照只能看版式，判定以这份文本为准）
    private static func writeDisplayStyleControls(directory: URL, pane: SettingsGeneralPane) {
        let card = pane.displayStyleCard
        let lines = [
            "# 菜单栏显示方式卡 · 控件真值",
            "标签档 title=\(card.labelControl.titleOfSelectedItem ?? "nil")"
                + " index=\(card.labelControl.indexOfSelectedItem)",
            "密度 title=\(card.densityControl.titleOfSelectedItem ?? "nil")",
            "单位 title=\(card.unitControl.titleOfSelectedItem ?? "nil")",
            "布局 title=\(card.layoutControl.titleOfSelectedItem ?? "nil")",
            "快捷模板 selected=\(card.templateControl.selectedSegment)",
            "逐项自定义 enabled=\(card.customButton.isEnabled)"
                + " label=\(card.customButton.accessibilityLabel() ?? "nil")",
        ]
        try? lines.joined(separator: "\n").write(
            to: directory.appendingPathComponent("settings-general-display-style-controls.txt"),
            atomically: true, encoding: .utf8)
    }
}


#endif