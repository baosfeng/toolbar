#if DEBUG
import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

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

    /// 剪贴板面板画布尺寸 —— 宽取 07-contract 的 640pt，高取分段几何的默认面板高（否则整卡被裁）
    ///
    /// 一处定义、各取证入口共用：详情区让面板变高后，散落的 640×260 常量会把卡片区裁掉。
    static let panelSize = NSSize(width: 640, height: ClipboardPanelLayout.defaultPanelHeight)

    private let size: NSSize
    private let items: [ClipboardItem]

    init(size: NSSize, items: [ClipboardItem]) {
        self.size = size
        self.items = items
    }

    /// 每次渲染生成一份新视图，避免上一次渲染遗留的选中态/布局残留
    ///
    /// - Parameters:
    ///   - selectedIDs: 选中集合（nil = 按 selectedIndex 单条选中；多选态显式给集合）
    ///   - hoveredIndex: 要置成 hover 态的卡片下标（nil = 都不 hover）
    func makeView(selectedIDs: Set<UUID>? = nil, hoveredIndex: Int? = nil) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let panelView = ClipboardPanelView(frame: NSRect(origin: .zero, size: size))
        panelView.autoresizingMask = [.width, .height]
        panelView.render(items: items, selectedIndex: items.isEmpty ? -1 : 0, selectedIDs: selectedIDs)
        if let hoveredIndex {
            let cards = panelView.cardFlow.cardViews
            if cards.indices.contains(hoveredIndex) {
                cards[hoveredIndex].applyHover(true, animated: false)
                cards[hoveredIndex].onShadowStateChange?()
            }
        }
        // 底部件数计数由控制器在 applyFilter 后灌入；快照直接按同口径补一次，保证截图与真机一致
        panelView.updateCounts(total: items.count, pinned: items.filter(\.isPinned).count)
        effect.addSubview(panelView)
        return effect
    }
}

    /// 写自证指标文本（仅快照目录内，便于 review 时不依赖肉眼）
    func writeSnapshotMetrics(directory: URL, needed: CGFloat, size: NSSize,
                                     metrics: (document: CGFloat, viewport: CGFloat)) {
        let text = """
        content_needed_pt = \(Int(needed.rounded()))
        popover_height_pt = \(Int(size.height))
        scroll_document_pt = \(Int(metrics.document.rounded()))
        scroll_viewport_pt = \(Int(metrics.viewport.rounded()))
        scrollable = \(metrics.document > metrics.viewport + 1)
        """ + "\n"
        let url = directory.appendingPathComponent("menu-network-stress-metrics.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        AppContext.shared.logger.info("超高自证：需要 \(Int(needed))pt，视口 \(Int(metrics.viewport))pt，文档 \(Int(metrics.document))pt")
    }
#endif