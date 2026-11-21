import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘行列表

/// 自绘行列表 —— **一个视图画 N 行**，不再为每行建 N 个 NSView
///
/// 与 AppKit 视图树方案的关系：
/// - 行名 / 行值 / 进度条三者由一次 `draw` 完成，视图数恒为 1；
/// - 交互（悬停高亮、点击、键盘焦点、无障碍）由本视图自己维护，且一律走 L4 交互层：
///   命中 `DrawnHitRegions`、悬停目标 `DrawnHoverState` + 过渡值 `DrawnBlend`、
///   焦点环 `DrawnFocusRing`、无障碍 `DrawnAccessibilityReporter`；
/// - 视觉令牌全部取自 `PaneCardStyle`，与现有面板逐像素同源、换主题零改动。
///
/// 行有两种排法（由 `DrawnRowSpec.isStacked` 决定）：
/// - 单行式：行名 → 进度条 → 行值（系统页进程榜、网络页进程榜）；
/// - 两行式：色点 + 行名 + 右侧两列，副文本整行，底部整行微条（Token 排行屏）。
/// 绘制实现在 `DrawnRowList+Drawing.swift`，本文件只管数据、几何、交互与无障碍。
@MainActor
package final class DrawnRowList: NSView {

    // MARK: - 数据

    /// 要画的行（值类型，变更即重绘）
    package var rows: [DrawnRowSpec] = [] {
        didSet {
            guard rows != oldValue else { return }
            if let focusedIndex, focusedIndex >= rows.count { self.focusedIndex = nil }
            // 行数变短：越界的悬停目标归零（在状态机里判，不在这里各写一遍）
            if hoverState.clamp(count: rows.count).isChanged { dropHoverTarget() }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            rebuildAccessibilityElements()
        }
    }

    // MARK: - 几何

    package var rowHeight: CGFloat = PaneCardStyle.rowHeight {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// 行间空隙
    package var rowSpacing: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// 行内左右内边距
    package var horizontalInset: CGFloat = PaneCardStyle.cardPaddingX {
        didSet { needsDisplay = true }
    }
    /// 名称 / 进度条 / 数值之间的间距
    package var elementGap: CGFloat = 6 { didSet { needsDisplay = true } }
    /// 行名字体（默认面板行名；系统页等更紧凑的页面按需覆盖）
    package var titleFont: NSFont = PaneCardStyle.rowNameFont { didSet { needsDisplay = true } }
    /// 行值字体（默认面板行值）
    package var valueFont: NSFont = PaneCardStyle.rowValueFont { didSet { needsDisplay = true } }
    /// 行名固定列宽（nil = 按文字实际宽度占位；非 nil 时按等宽列排布，超宽截断）
    package var fixedTitleWidth: CGFloat? { didSet { needsDisplay = true } }
    /// 行悬停提示（返回空串则不提示）
    package var rowToolTip: ((Int) -> String)?
    /// 行前图标（网络页的进程图标；返回 nil 则这一行不画图标）
    package var rowIcon: ((Int) -> NSImage?)?
    /// 行前图标边长（0 = 不画图标列，行名从最左开始）
    package var iconSize: CGFloat = 0 { didSet { needsDisplay = true } }
    /// 模板图标的上色（nil = 原样绘制）
    package var iconTint: NSColor? { didSet { needsDisplay = true } }
    /// 行前色点取色（两行式）；同一行底部微条也用它取色，保证点与条对得上
    package var rowSwatchColor: ((Int) -> NSColor?)? { didSet { needsDisplay = true } }
    /// 色点边长（6pt：与 Token 页图例色点同形）
    package var swatchSize: CGFloat = 6 { didSet { needsDisplay = true } }
    /// 副文本字体（两行式的第二行）
    package var detailFont: NSFont = PaneCardStyle.metaFont { didSet { needsDisplay = true } }
    /// 副文本颜色
    package var detailColor: NSColor = PaneCardStyle.tertiaryText { didSet { needsDisplay = true } }
    /// 右侧第二列字体（两行式的占比等）
    package var secondaryFont: NSFont = PaneCardStyle.metaFont { didSet { needsDisplay = true } }
    /// 右侧第二列颜色
    package var secondaryColor: NSColor = PaneCardStyle.tertiaryText { didSet { needsDisplay = true } }
    /// 行名颜色（默认主文字；系统页等按需覆盖）
    package var titleColor: NSColor = PaneCardStyle.primaryText { didSet { needsDisplay = true } }
    /// 进度条轨道色
    package var trackColor: NSColor = PaneCardStyle.trackColor { didSet { needsDisplay = true } }
    /// 进度条填充色（告警语气固定用警示色）
    package var barColor: NSColor = PaneCardStyle.okColor { didSet { needsDisplay = true } }

    /// 进度条可画的最小宽度（不足则整条不画）
    ///
    /// 取 36 而不是视觉最小 24：长标题把进度条挤到 24–36 时会变成一个小色块，
    /// 比「不画」更难看，宁可整条省略、把宽度还给标题。
    package var minBarWidth: CGFloat = 60 { didSet { needsDisplay = true } }
    /// 进度条高度
    package var barHeight: CGFloat = 5 { didSet { needsDisplay = true } }

    // MARK: - 交互

    /// 点击某行（下标）
    package var onRowAction: ((Int) -> Void)?
    /// 键盘焦点行（nil = 无焦点）
    package var focusedIndex: Int? {
        didSet { if focusedIndex != oldValue { needsDisplay = true } }
    }
    /// 是否绘制悬停高亮（纯展示列表可关掉）
    package var highlightsHover = true

    /// 悬停目标推进（纯状态机：进入 / 离开 / 跨行；口径在 `DrawnHoverState`）
    private var hoverState = DrawnHoverState()
    /// 悬停过渡值（0 = 常态，1 = 高亮满；只在高亮变化的那 0.12s 里有 Timer）
    /// internal：绘制实现在 DrawnRowList+Drawing.swift 里读它（Swift 扩展不能声明存储属性）
    package let hoverBlend = DrawnBlend()
    /// 正在绘制的悬停行 —— 离开时保留到淡出结束，避免「移出即消失」；
    /// 跨文件绘制实现要读，故放宽为 internal
    package private(set) var hoverIndex: Int?

    // MARK: - 布局

    package override var isFlipped: Bool { true }

    package override var intrinsicContentSize: NSSize {
        let h = DrawnRowLayout.contentHeight(rowCount: rows.count,
                                              rowHeight: rowHeight,
                                              rowSpacing: rowSpacing)
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }

    /// 第 index 行的矩形（flipped 坐标，自上而下）
    package func rowRect(_ index: Int) -> CGRect {
        CGRect(x: 0,
               y: CGFloat(index) * (rowHeight + rowSpacing),
               width: bounds.width,
               height: rowHeight)
    }

    /// 某点落在哪一行（落在行间空隙返回 nil）
    ///
    /// 纯口径在 `DrawnHitRegions.bandIndex`（含边缘 / 空隙 / 越界的边界行为由 TestRunner 钉住）。
    func rowIndex(at point: NSPoint) -> Int? {
        DrawnHitRegions.bandIndex(at: point,
                                  bandHeight: rowHeight,
                                  step: rowHeight + rowSpacing,
                                  count: rows.count)
    }

    // MARK: - 绘制入口

    package override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        for (index, row) in rows.enumerated() {
            let rect = rowRect(index)
            guard rect.intersects(dirtyRect) else { continue }
            drawRow(row, index: index, in: rect)
        }
        ctx.restoreGState()
    }

    // MARK: - 鼠标

    package override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeInKeyWindow, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    package override func mouseMoved(with event: NSEvent) {
        guard highlightsHover else { return }
        advanceHover(to: rowIndex(at: convert(event.locationInWindow, from: nil)))
    }

    package override func mouseExited(with event: NSEvent) {
        advanceHover(to: nil)
    }

    // MARK: - 悬停推进（目标走状态机，过渡值走 DrawnBlend）

    /// 推进悬停目标并驱动过渡
    ///
    /// 三种变化各自的结果：进入 → 新行从 0 淡入；跨行 → 旧行让位、新行淡入；
    /// 离开 → 旧行淡出到 0 后再停止绘制（所以 hoverIndex 要留到淡出结束）。
    private func advanceHover(to index: Int?) {
        let change = hoverState.move(to: index)
        guard change.isChanged else { return }
        switch change {
        case .none:
            return
        case .entered, .moved:
            hoverIndex = index
            hoverBlend.set(0)
            hoverBlend.animate(to: 1, onChange: refreshHoverFrame)
        case .left:
            hoverBlend.animate(to: 0, onChange: refreshHoverFrame)
        }
        needsDisplay = true
    }

    /// 悬停目标被外部条件清掉（行数变短）：不走淡出，直接收
    private func dropHoverTarget() {
        hoverBlend.cancel()
        hoverBlend.set(0)
        hoverIndex = nil
        needsDisplay = true
    }

    /// 过渡帧回调：淡出到底后停止绘制悬停行
    private func refreshHoverFrame(_ value: CGFloat) {
        if value <= 0.001, !hoverState.isHovering, hoverIndex != nil { hoverIndex = nil }
        needsDisplay = true
    }

    package override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rowIndex(at: point), rows[index].isActionable else {
            super.mouseDown(with: event)
            return
        }
        onRowAction?(index)
    }

    // MARK: - 悬停提示

    private var toolTipTag: NSView.ToolTipTag?
    /// 上次挂 tooltip 时的 bounds（bounds 不变就不重挂）
    private var toolTipBounds: CGRect = .null

    /// 整块挂一个 tooltip，按坐标反查行
    ///
    /// 只在 bounds 变化时重挂：旧实现在**每次布局**都 remove + add 一个 tooltip，
    /// 重建一遍 tooltip tracking 是纯浪费（面板展开时布局并不罕见），而 tooltip 矩形
    /// 只跟 view 尺寸有关，行数变化由 `rowIndex(at:)` 现算，本就不需要重挂。
    private func refreshToolTipIfNeeded() {
        guard toolTipTag == nil || bounds != toolTipBounds else { return }
        if let toolTipTag { removeToolTip(toolTipTag) }
        toolTipTag = addToolTip(bounds, owner: self, userData: nil)
        toolTipBounds = bounds
    }

    @objc func view(_ view: NSView,
                    stringForToolTip tag: NSView.ToolTipTag,
                    point: NSPoint,
                    userData data: UnsafeMutableRawPointer?) -> String {
        guard let index = rowIndex(at: point) else { return "" }
        return rowToolTip?(index) ?? ""
    }

    package override func layout() {
        super.layout()
        refreshToolTipIfNeeded()
    }

    // MARK: - 无障碍

    private var axElements: [DrawnRowAccessibilityElement] = []

    private func rebuildAccessibilityElements() {
        axElements = rows.enumerated().map { index, row in
            DrawnAccessibilityReporter.element(role: row.isActionable ? .button : .staticText,
                                               label: accessibilityText(for: row),
                                               parent: self,
                                               activate: row.isActionable
                                                   ? { [weak self] in self?.onRowAction?(index) } : nil)
        }
        // 列表本身是「组」：整块一个节点，行由 accessibilityChildren 逐行挂上去
        DrawnAccessibilityReporter.configure(self, role: .group, label: "列表")
    }

    /// 一行的读屏文案：两行式把副文本也读出来，否则占比 / 会话数读屏就丢了
    private func accessibilityText(for row: DrawnRowSpec) -> String {
        DrawnAccessibilityText.row(title: row.title, value: row.value,
                                   secondary: row.secondary, detail: row.detail)
    }

    package override func accessibilityChildren() -> [Any]? {
        if axElements.count != rows.count { rebuildAccessibilityElements() }
        for (index, element) in axElements.enumerated() {
            element.setAccessibilityFrame(
                DrawnAccessibilityReporter.screenFrame(of: rowRect(index), in: self))
        }
        return axElements
    }
}
