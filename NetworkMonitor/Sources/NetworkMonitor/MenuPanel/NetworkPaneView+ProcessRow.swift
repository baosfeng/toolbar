import AppKit
import NetworkMonitorCore

// MARK: - 网络页进程行（拆出 NetworkPaneView.swift）

/// 活跃进程行 — 真实 App 图标（`NSWorkspace.icon(forFile:)`）+ 进程名 + 上下行速率
///
/// 从主文件拆出：`NetworkPaneView.swift` 加 Wi-Fi 链路条后越过单文件 15 KiB 门禁，
/// 而行视图本就与页面装配无关，是最干净的一刀。
final class MenuPanelProcessRow: MenuPanelRow {
    private let iconView = NSImageView()

    init(process: ProcessNetUsage) {
        super.init(height: MenuPanelStyle.compactRowHeight, onClick: nil)

        // 本应用那行显示「一览」；图标仍按原始进程名 + pid 解析（解析主路径走 pid，不受显示名影响）
        let displayName = AppProcessName.displayName(process.name, pid: process.pid)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.image = AppIconProvider.icon(forProcess: process.name, pid: process.pid, size: 20)
            ?? AppIconProvider.placeholderIcon(size: 20)
        iconView.contentTintColor = MenuPanelStyle.tertiaryText
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])
        contentStack.addArrangedSubview(iconView)

        contentStack.addArrangedSubview(MenuPanelLabel.text(displayName, font: MenuPanelStyle.bodyFont))
        contentStack.addArrangedSubview(MenuPanelLabel.spacer())

        let downText = "↓" + formatSpeedShort(Double(process.bytesIn))
        let upText = "↑" + formatSpeedShort(Double(process.bytesOut))
        let speeds = MenuPanelLabel.text("\(downText)  \(upText)", font: MenuPanelStyle.smallValueFont,
                                        color: MenuPanelStyle.secondaryText)
        speeds.setContentHuggingPriority(.required, for: .horizontal)
        contentStack.addArrangedSubview(speeds)
    }
}
