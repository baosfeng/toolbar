#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照：系统页滚到底 / 超高内容自证（仅 DEBUG）

/// 从 `MenuPanelSnapshot.swift` 拆出（主文件贴顶 15 KiB 上限）
///
/// 这两块都是「补一张首屏看不到的角度」：系统页底部状态带要滚到底才可见，
/// 超高自证要证明内容没被裁切而是变成可滚动。
extension MenuPanelSnapshot {

    /// 系统页「滚到底」取证：底部状态带（温度 / 电池环 / 估功耗）只在滚动后可见
    static func captureSystemScrolledBottom(directory: URL, items: [ClipboardItem]) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let panel = makeMenuPanel(tab: .system, items: items)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
            render(view: panel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-system-bottom-\(suffix).png")) { view in
                (view as? MenuPanelView)?.scrollToBottomForSnapshot()
            }
        }
    }

    /// 超高内容自证：把进程数拉到 12（内容 > 520pt），截「视口顶部」与「滚到底部」两张图，
    /// 并把文档高度 / 视口高度写进 metrics 文本，证明内容没有被裁切、而是变成可滚动。
    static func captureStress(directory: URL, items: [ClipboardItem]) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            let panel = makeMenuPanel(tab: .network, items: items, processCount: 12)
            let needed = panel.desiredContentHeight
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)

            render(view: panel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-network-stress-\(suffix).png"))

            let scrolledPanel = makeMenuPanel(tab: .network, items: items, processCount: 12)
            render(view: scrolledPanel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-network-stress-\(suffix)-scrolled.png")) { view in
                guard let panel = view as? MenuPanelView else { return }
                let metrics = panel.snapshotScrollMetrics()
                panel.scrollToBottomForSnapshot()
                writeSnapshotMetrics(directory: directory, needed: needed, size: size, metrics: metrics)
            }
        }
    }
}
#endif
