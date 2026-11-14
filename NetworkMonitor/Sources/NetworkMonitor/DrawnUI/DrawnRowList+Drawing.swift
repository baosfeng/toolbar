import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 行绘制（单行式 / 两行式）

/// 行的绘制实现 — 从 `DrawnRowList.swift` 拆出（主文件加两行式后越过单文件体积门禁）
///
/// 拆法按职责而不是按类型：本文件只管「把一行画出来」，
/// 数据、几何、鼠标与无障碍仍在主文件。跨文件要读的成员已在主文件放宽为 internal 并注明原因。
/// 两行式第一行的列几何 — 绘制与快照度量共用同一份计算，避免「量的是一套、画的是另一套」
struct DrawnStackedHeadMetrics {
    let titleX: CGFloat
    let titleWidth: CGFloat
    /// 行名完整显示所需宽度（> titleWidth 即截断）
    let titleNeeded: CGFloat
    let valueWidth: CGFloat
    let secondaryWidth: CGFloat
    let titleH: CGFloat
    let detailH: CGFloat
}

extension DrawnRowList {

    /// 画一行：有副文本走两行式，否则单行式
    func drawRow(_ row: DrawnRowSpec, index: Int, in rect: CGRect) {
        // 悬停底：整层不透明度由过渡值给（静止在 0 时整层不画，与改造前的静态帧逐像素一致）
        if highlightsHover, hoverIndex == index, hoverBlend.value > 0.001 {
            DrawnCardSurface(rect: rect.insetBy(dx: 0, dy: 1), radius: 4,
                             fill: PaneCardStyle.selectedFill,
                             alpha: hoverBlend.value).draw()
        }
        if row.isStacked {
            drawStackedRow(row, index: index, in: rect)
        } else {
            drawSingleRow(row, index: index, in: rect)
        }
        drawFocusRing(index: index, in: rect)
    }

    // MARK: 单行式

    /// 行名 → 进度条 → 行值（行内垂直居中）
    ///
    /// 绘制主体在 DrawnSingleRowStyle：自绘卡片里的行不建视图，但两条路径必须画出同一种行。
    /// 图标由本视图补（只有列表才有图标来源），位置与宽度走同一套列宽分配。
    private func drawSingleRow(_ row: DrawnRowSpec, index: Int, in rect: CGRect) {
        let iconWidth = iconSize > 0 ? iconSize : 0
        if iconWidth > 0, let image = rowIcon?(index) {
            // 图标列始终占位（这行取不到图标也留空），保证行名左对齐整齐
            DrawnSymbolRun.drawFitted(image,
                                      in: CGRect(x: rect.minX + horizontalInset,
                                                 y: rect.midY - iconWidth / 2,
                                                 width: iconWidth,
                                                 height: iconWidth),
                                      tint: iconTint)
        }
        singleRowStyle.draw(row, in: rect, leadingWidth: iconWidth)
    }

    /// 当前配置对应的单行式绘制器（行列表与自绘卡片共用）
    private var singleRowStyle: DrawnSingleRowStyle {
        DrawnSingleRowStyle(horizontalInset: horizontalInset,
                            elementGap: elementGap,
                            titleFont: titleFont,
                            valueFont: valueFont,
                            titleColor: titleColor,
                            trackColor: trackColor,
                            barColor: barColor,
                            barHeight: barHeight,
                            minBarWidth: minBarWidth,
                            fixedTitleWidth: fixedTitleWidth)
    }

    // MARK: 两行式

    /// 两行式：第一行「色点 + 行名 + 右两列（值、次列）」，第二行副文本，底部整行微条
    ///
    /// 行高由外部给（排行屏按可见行数均分），内容块（主行 + 副行 + 微条）整体垂直居中，
    /// 行高 34pt 与 48pt 都不会贴边。
    private func drawStackedRow(_ row: DrawnRowSpec, index: Int, in rect: CGRect) {
        let content = stackedContentRect(in: rect)
        guard content.width > 0 else { return }

        let titleRun = DrawnTextRun(string: row.title, font: titleFont, color: titleColor)
        let valueRun = DrawnTextRun(string: row.value,
                                    font: row.tone == .strong ? PaneCardStyle.rowValueStrongFont : valueFont,
                                    color: toneColor(row.tone))
        let secondaryRun = DrawnTextRun(string: row.secondary, font: secondaryFont, color: secondaryColor)
        let detailRun = DrawnTextRun(string: row.detail, font: detailFont, color: detailColor)
        let head = stackedHeadMetrics(row, in: content)
        let top = stackedTop(head, in: content)

        // 第一行：色点 → 行名 → 值 → 次列（右对齐，次列贴最右）
        if row.showsSwatch, let color = rowSwatchColor?(index) {
            let side = swatchSize
            DrawnInk.swatch(in: CGRect(x: content.minX,
                                       y: top + head.titleH / 2 - side / 2,
                                       width: side,
                                       height: side),
                            color: color)
        }
        var rightEdge = content.maxX
        if head.secondaryWidth > 0 {
            secondaryRun.draw(in: CGRect(x: rightEdge - head.secondaryWidth,
                                         y: top,
                                         width: head.secondaryWidth,
                                         height: head.titleH),
                              alignment: .right)
            rightEdge -= head.secondaryWidth + elementGap
        }
        if head.valueWidth > 0 {
            valueRun.draw(in: CGRect(x: rightEdge - head.valueWidth,
                                     y: top,
                                     width: head.valueWidth,
                                     height: head.titleH),
                          alignment: .right)
        }
        if head.titleWidth > 0 {
            titleRun.draw(in: CGRect(x: head.titleX,
                                     y: top,
                                     width: head.titleWidth,
                                     height: head.titleH))
        }

        // 第二行：副文本整行
        detailRun.draw(in: CGRect(x: content.minX,
                                  y: top + head.titleH + Self.stackedLineGap,
                                  width: content.width,
                                  height: head.detailH))

        // 底部微条：整行宽，颜色与色点同源（一眼能对上行列）
        if let progress = row.progress {
            let barRect = CGRect(x: content.minX,
                                 y: top + head.titleH + Self.stackedLineGap + head.detailH + Self.stackedLineGap,
                                 width: content.width,
                                 height: barHeight)
            DrawnInk.progressBar(in: barRect,
                                 progress: progress,
                                 track: trackColor,
                                 fill: rowSwatchColor?(index) ?? barColor,
                                 radius: barHeight / 2)
        }
    }

    // MARK: 两行式几何（绘制与快照度量共用）

    /// 两行式的行间文字间距
    static let stackedLineGap: CGFloat = 2

    /// 两行式的内容区（左右内边距之内）
    func stackedContentRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + horizontalInset,
               y: rect.minY,
               width: max(rect.width - horizontalInset * 2, 0),
               height: rect.height)
    }

    /// 内容块（主行 + 副行 + 微条）的顶边：整体在行内垂直居中
    func stackedTop(_ head: DrawnStackedHeadMetrics, in content: CGRect) -> CGFloat {
        let blockH = head.titleH + Self.stackedLineGap + head.detailH + Self.stackedLineGap + barHeight
        return content.midY - blockH / 2
    }
    /// 两行式第一行的列宽：次列贴最右、值次之、行名吃剩余（放不下就截断）
    func stackedHeadMetrics(_ row: DrawnRowSpec, in content: CGRect) -> DrawnStackedHeadMetrics {
        let titleRun = DrawnTextRun(string: row.title, font: titleFont, color: titleColor)
        let valueRun = DrawnTextRun(string: row.value,
                                    font: row.tone == .strong ? PaneCardStyle.rowValueStrongFont : valueFont,
                                    color: toneColor(row.tone))
        let secondaryRun = DrawnTextRun(string: row.secondary, font: secondaryFont, color: secondaryColor)
        // 色点列始终占位（与单行式的图标列同理），行名从它右侧开始
        let headX = content.minX + (row.showsSwatch ? swatchSize + elementGap : 0)
        var rightEdge = content.maxX
        let secondaryWidth = row.secondary.isEmpty
            ? 0 : min(secondaryRun.width(), max(content.width, 0))
        rightEdge -= secondaryWidth
        if secondaryWidth > 0 { rightEdge -= elementGap }
        let valueWidth = row.value.isEmpty
            ? 0 : valueRun.width(limit: max(rightEdge - headX, 0))
        rightEdge -= valueWidth
        if valueWidth > 0 { rightEdge -= elementGap }
        return DrawnStackedHeadMetrics(
            titleX: headX,
            titleWidth: max(rightEdge - headX, 0),
            titleNeeded: titleRun.width(limit: .greatestFiniteMagnitude),
            valueWidth: valueWidth,
            secondaryWidth: secondaryWidth,
            titleH: titleRun.lineHeight,
            detailH: DrawnTextRun(string: row.detail, font: detailFont, color: detailColor).lineHeight)
    }
    // MARK: 焦点环 / 语气色

    /// 键盘焦点环（自绘，不依赖系统 focus ring；绘制在 DrawnFocusRing.drawRow）
    private func drawFocusRing(index: Int, in rect: CGRect) {
        guard focusedIndex == index else { return }
        DrawnFocusRing.drawRow(in: rect)
    }

    private func toneColor(_ tone: DrawnRowSpec.Tone) -> NSColor {
        switch tone {
        case .normal: return PaneCardStyle.secondaryText
        case .strong: return PaneCardStyle.primaryText
        case .warning: return PaneCardStyle.warnInk
        }
    }
}

#if DEBUG
/// 两行式一行的度量（快照台账用：名称 / 数值的可用与所需宽度、行高）
struct DrawnStackedRowMetrics {
    let titleAvailable: CGFloat
    let titleNeeded: CGFloat
    let titleHeight: CGFloat
    let valueAvailable: CGFloat
    let valueNeeded: CGFloat
    let rowWidth: CGFloat
    let rowHeight: CGFloat
}

extension DrawnRowList {

    /// 快照自证：两行式某一行的度量（行本身不是视图，只能从这里量）
    func stackedRowMetricsForSnapshot(_ index: Int) -> DrawnStackedRowMetrics? {
        guard rows.indices.contains(index) else { return nil }
        let row = rows[index]
        let rect = rowRect(index)
        let content = stackedContentRect(in: rect)
        let head = stackedHeadMetrics(row, in: content)
        // 数值列「完整所需」按无宽度上限重算（可用宽已按行宽截断）
        let valueRun = DrawnTextRun(string: row.value,
                                    font: row.tone == .strong ? PaneCardStyle.rowValueStrongFont : valueFont,
                                    color: toneColor(row.tone))
        let secondaryRun = DrawnTextRun(string: row.secondary,
                                        font: secondaryFont,
                                        color: secondaryColor)
        let valueNeeded = valueRun.width(limit: .greatestFiniteMagnitude)
            + secondaryRun.width(limit: .greatestFiniteMagnitude)
            + (row.value.isEmpty || row.secondary.isEmpty ? 0 : elementGap)
        // 值 + 次列合计实到宽度：两者之间的间距也要算进去，否则台账会误报「数值被截断」
        let valueAvailable = head.valueWidth + head.secondaryWidth
            + (head.valueWidth > 0 && head.secondaryWidth > 0 ? elementGap : 0)
        return DrawnStackedRowMetrics(titleAvailable: head.titleWidth,
                                      titleNeeded: head.titleNeeded,
                                      titleHeight: head.titleH,
                                      valueAvailable: valueAvailable,
                                      valueNeeded: valueNeeded,
                                      rowWidth: rect.width,
                                      rowHeight: rect.height)
    }

    /// 快照自证：某行的悬停文案（toolTip 由 `rowToolTip` 回调提供）
    func rowTipForSnapshot(_ index: Int) -> String {
        guard rows.indices.contains(index) else { return "" }
        return rowToolTip?(index) ?? ""
    }
}
#endif