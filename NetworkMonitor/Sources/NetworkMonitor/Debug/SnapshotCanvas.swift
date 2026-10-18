#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 快照画布容器

/// 快照背景 — 用系统窗口背景色填充，让半透明材质下的深浅色差异可判读
///
/// 由 `MenuPanelSnapshot.render` 使用；拆到独立文件是为了让
/// `MenuPanelSnapshot.swift` 回到单文件体积上限（≤15 KiB）内。
final class SnapshotBackdropView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        super.draw(dirtyRect)
    }
}

// MARK: - 剪贴板面板画布

/// 剪贴板面板画布 — 复刻 ClipboardPanelController 的真实层次：材质底（14pt 圆角）+ 面板视图
@MainActor
final class SnapshotClipboardPanel {
    private let size: NSSize
    private let items: [ClipboardItem]

    init(size: NSSize, items: [ClipboardItem]) {
        self.size = size
        self.items = items
    }

    /// 每次渲染生成一份新视图，避免上一次渲染遗留的选中态/布局残留
    func makeView() -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let panelView = ClipboardPanelView(frame: NSRect(origin: .zero, size: size))
        panelView.autoresizingMask = [.width, .height]
        panelView.render(items: items, selectedIndex: items.isEmpty ? -1 : 0)
        effect.addSubview(panelView)
        return effect
    }
}
#endif
