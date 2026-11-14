import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘行列表

/// 可点击行的无障碍元素 —— 让 VoiceOver 能把自绘行当按钮按
final class DrawnRowAccessibilityElement: NSAccessibilityElement {
    var activate: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        guard let activate else { return false }
        activate()
        return true
    }
}

/// 自绘行列表 —— **一个视图画 N 行**，不再为每行建 N 个 NSView
///
/// 与 AppKit 视图树方案的关系：
/// - 行名 / 行值 / 进度条三者由一次 `draw` 完成，视图数恒为 1；
/// - 交互（悬停高亮、点击、键盘焦点、无障碍）由本视图自己维护；
/// - 视觉令牌全部取自 `PaneCardStyle`，与现有面板逐像素同源、换主题零改动。
///
/// 行有两种排法（由 `DrawnRowSpec.isStacked` 决定）：
/// - 单行式：行名 → 进度条 → 行值（系统页进程榜、网络页进程榜）；
/// - 两行式：色点 + 行名 + 右侧两列，副文本整行，底部整行微条（Token 排行屏）。
/// 绘制实现在 `DrawnRowList+Drawing.swift`，本文件只管数据、几何、交互与无障碍。
@MainActor
final class DrawnRowList: NSView {

    // MARK: - 数据

    /// 要画的行（值类型，变更即重绘）
    var rows: [DrawnRowSpec] = [] {
        didSet {
            guard rows != oldValue else { return }
            if let focusedIndex, focusedIndex >= rows.count { self.focusedIndex = nil }
            if let hoverIndex, hoverIndex >= rows.count { self.hoverIndex = nil }
            invalidateIntrinsicContentSize()
            needsDisplay = true
            rebuildAccessibilityElements()
        }
    }

    // MARK: - 几何

    var rowHeight: CGFloat = PaneCardStyle.rowHeight {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// 行间空隙
    var rowSpacing: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    /// 行内左右内边距
    var horizontalInset: CGFloat = PaneCardStyle.cardPaddingX {
        didSet { needsDisplay = true }
    }
    /// 名称 / 进度条 / 数值之间的间距
    var elementGap: CGFloat = 6 { didSet { needsDisplay = true } }
    /// 行名字体（默认面板行名；系统页等更紧凑的页面按需覆盖）
    var titleFont: NSFont = PaneCardStyle.rowNameFont { didSet { needsDisplay = true } }
    /// 行值字体（默认面板行值）
    var valueFont: NSFont = PaneCardStyle.rowValueFont { didSet { needsDisplay = true } }
    /// 行名固定列宽（nil = 按文字实际宽度占位；非 nil 时按等宽列排布，超宽截断）
    var fixedTitleWidth: CGFloat? { didSet { needsDisplay = true } }
    /// 行悬停提示（返回空串则不提示）
    var rowToolTip: ((Int) -> String)?
    /// 行前图标（网络页的进程图标；返回 nil 则这一行不画图标）
    var rowIcon: ((Int) -> NSImage?)?
    /// 行前图标边长（0 = 不画图标列，行名从最左开始）
    var iconSize: CGFloat = 0 { didSet { needsDisplay = true } }
    /// 模板图标的上色（nil = 原样绘制）
    var iconTint: NSColor? { didSet { needsDisplay = true } }
    /// 行前色点取色（两行式）；同一行底部微条也用它取色，保证点与条对得上
    var rowSwatchColor: ((Int) -> NSColor?)? { didSet { needsDisplay = true } }
    /// 色点边长（6pt：与 Token 页图例色点同形）
    var swatchSize: CGFloat = 6 { didSet { needsDisplay = true } }
    /// 副文本字体（两行式的第二行）
    var detailFont: NSFont = PaneCardStyle.metaFont { didSet { needsDisplay = true } }
    /// 副文本颜色
    var detailColor: NSColor = PaneCardStyle.tertiaryText { didSet { needsDisplay = true } }
    /// 右侧第二列字体（两行式的占比等）
    var secondaryFont: NSFont = PaneCardStyle.metaFont { didSet { needsDisplay = true } }
    /// 右侧第二列颜色
    var secondaryColor: NSColor = PaneCardStyle.tertiaryText { didSet { needsDisplay = true } }
    /// 行名颜色（默认主文字；系统页等按需覆盖）
    var titleColor: NSColor = PaneCardStyle.primaryText { didSet { needsDisplay = true } }
    /// 进度条轨道色
    var trackColor: NSColor = PaneCardStyle.trackColor { didSet { needsDisplay = true } }
    /// 进度条填充色（告警语气固定用警示色）
    var barColor: NSColor = PaneCardStyle.okColor { didSet { needsDisplay = true } }

    /// 进度条可画的最小宽度（不足则整条不画）
    ///
    /// 取 36 而不是视觉最小 24：长标题把进度条挤到 24–36 时会变成一个小色块，
    /// 比「不画」更难看，宁可整条省略、把宽度还给标题。
    var minBarWidth: CGFloat = 60 { didSet { needsDisplay = true } }
    /// 进度条高度
    var barHeight: CGFloat = 5 { didSet { needsDisplay = true } }

    // MARK: - 交互

    /// 点击某行（下标）
    var onRowAction: ((Int) -> Void)?
    /// 键盘焦点行（nil = 无焦点）
    var focusedIndex: Int? {
        didSet { if focusedIndex != oldValue { needsDisplay = true } }
    }
    /// 是否绘制悬停高亮（纯展示列表可关掉）
    var highlightsHover = true
    /// 悬停行 —— 跨文件绘制实现要读，故放宽为 internal
    var hoverIndex: Int? {
        didSet { if hoverIndex != oldValue { needsDisplay = true } }
    }
    /// 模板图标的上色缓存（键 = 图标对象身份；绘制实现跨文件使用，故 internal）
    var tintedIcons: [ObjectIdentifier: NSImage] = [:]

    // MARK: - 布局

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let h = DrawnRowLayout.contentHeight(rowCount: rows.count,
                                              rowHeight: rowHeight,
                                              rowSpacing: rowSpacing)
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }

    /// 第 index 行的矩形（flipped 坐标，自上而下）
    func rowRect(_ index: Int) -> CGRect {
        CGRect(x: 0,
               y: CGFloat(index) * (rowHeight + rowSpacing),
               width: bounds.width,
               height: rowHeight)
    }

    /// 某点落在哪一行（落在行间空隙返回 nil）
    func rowIndex(at point: NSPoint) -> Int? {
        guard !rows.isEmpty else { return nil }
        let step = rowHeight + rowSpacing
        guard step > 0, point.y >= 0 else { return nil }
        let index = Int((point.y / step).rounded(.down))
        guard index >= 0, index < rows.count else { return nil }
        return point.y - CGFloat(index) * step <= rowHeight ? index : nil
    }

    // MARK: - 绘制入口

    override func draw(_ dirtyRect: NSRect) {
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited,
                                                 .activeInKeyWindow, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        guard highlightsHover else { return }
        hoverIndex = rowIndex(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = rowIndex(at: point), rows[index].isActionable else {
            super.mouseDown(with: event)
            return
        }
        onRowAction?(index)
    }

    // MARK: - 悬停提示

    private var toolTipTag: NSView.ToolTipTag?

    /// 整块挂一个 tooltip，按坐标反查行（行数变化不需要重挂）
    private func refreshToolTip() {
        if let toolTipTag { removeToolTip(toolTipTag) }
        toolTipTag = addToolTip(bounds, owner: self, userData: nil)
    }

    @objc func view(_ view: NSView,
                    stringForToolTip tag: NSView.ToolTipTag,
                    point: NSPoint,
                    userData data: UnsafeMutableRawPointer?) -> String {
        guard let index = rowIndex(at: point) else { return "" }
        return rowToolTip?(index) ?? ""
    }

    override func layout() {
        super.layout()
        refreshToolTip()
    }

    // MARK: - 无障碍

    private var axElements: [DrawnRowAccessibilityElement] = []

    private func rebuildAccessibilityElements() {
        axElements = rows.enumerated().map { index, row in
            let element = DrawnRowAccessibilityElement()
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(row.isActionable ? .button : .staticText)
            element.setAccessibilityLabel(accessibilityText(for: row))
            if row.isActionable {
                element.activate = { [weak self] in self?.onRowAction?(index) }
            }
            return element
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("列表")
    }

    /// 一行的读屏文案：两行式把副文本也读出来，否则占比 / 会话数读屏就丢了
    private func accessibilityText(for row: DrawnRowSpec) -> String {
        var parts = [row.title]
        if !row.value.isEmpty { parts.append(row.value) }
        if !row.secondary.isEmpty { parts.append(row.secondary) }
        if !row.detail.isEmpty { parts.append(row.detail) }
        return parts.joined(separator: " ")
    }

    override func accessibilityChildren() -> [Any]? {
        if axElements.count != rows.count { rebuildAccessibilityElements() }
        for (index, element) in axElements.enumerated() {
            element.setAccessibilityFrame(screenFrame(of: rowRect(index)))
        }
        return axElements
    }

    private func screenFrame(of rect: CGRect) -> CGRect {
        guard let window else { return rect }
        return window.convertToScreen(convert(rect, to: nil))
    }
}
