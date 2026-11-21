import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 单行式一行的绘制（不建视图）

/// 单行式一行（行名 → 进度条 → 行值）的绘制配置与绘制本身
///
/// 抽出来是为了让「行列表」与「整卡自绘」共用同一段绘制：`DrawnRowList` 仍是可交互的
/// 行列表视图（悬停 / 点击 / 焦点 / 无障碍），自绘卡片里的行只是几行文字与一条进度条，
/// 没必要为它建视图，但两者画出来的东西必须一模一样。
///
/// 列宽分配走 `DrawnRowLayout.metrics`（纯逻辑，已断言），本类型只负责按算好的矩形画。
@MainActor
public struct DrawnSingleRowStyle {

    /// 行内左右内边距
    var horizontalInset: CGFloat = PaneCardStyle.cardPaddingX
    /// 名称 / 进度条 / 数值之间的间距
    var elementGap: CGFloat = 6
    /// 行名字体
    var titleFont: NSFont = PaneCardStyle.rowNameFont
    /// 行值字体（强调行换粗体）
    var valueFont: NSFont = PaneCardStyle.rowValueFont
    /// 行名颜色
    var titleColor: NSColor = PaneCardStyle.primaryText
    /// 进度条轨道色
    var trackColor: NSColor = PaneCardStyle.trackColor
    /// 进度条填充色
    var barColor: NSColor = PaneCardStyle.okColor
    /// 进度条高度
    var barHeight: CGFloat = 5
    /// 进度条可画的最小宽度（不足则整条不画）
    var minBarWidth: CGFloat = 60
    /// 行名固定列宽（nil = 按文字实际宽度占位）
    var fixedTitleWidth: CGFloat?

    public init(horizontalInset: CGFloat = PaneCardStyle.cardPaddingX,
                elementGap: CGFloat = 6,
                titleFont: NSFont = PaneCardStyle.rowNameFont,
                valueFont: NSFont = PaneCardStyle.rowValueFont,
                titleColor: NSColor = PaneCardStyle.primaryText,
                trackColor: NSColor = PaneCardStyle.trackColor,
                barColor: NSColor = PaneCardStyle.okColor,
                barHeight: CGFloat = 5,
                minBarWidth: CGFloat = 60,
                fixedTitleWidth: CGFloat? = nil) {
        self.horizontalInset = horizontalInset
        self.elementGap = elementGap
        self.titleFont = titleFont
        self.valueFont = valueFont
        self.titleColor = titleColor
        self.trackColor = trackColor
        self.barColor = barColor
        self.barHeight = barHeight
        self.minBarWidth = minBarWidth
        self.fixedTitleWidth = fixedTitleWidth
    }

    /// 画一行
    /// - Parameters:
    ///   - row: 行规格
    ///   - rect: 行矩形（flipped 坐标）
    ///   - leadingWidth: 行名左侧固定占用宽度（图标列；0 = 无），它之后再吃一个间距
    public func draw(_ row: DrawnRowSpec, in rect: CGRect, leadingWidth: CGFloat = 0) {
        let titleRun = DrawnTextRun(string: row.title, font: titleFont, color: titleColor)
        let valueRun = DrawnTextRun(
            string: row.value,
            font: row.tone == .strong ? PaneCardStyle.rowValueStrongFont : valueFont,
            color: row.tone == .warning ? PaneCardStyle.warnInk : toneColor(row.tone))
        let iconWidth = max(leadingWidth, 0)
        let metrics = DrawnRowLayout.metrics(rowWidth: rect.width,
                                             leadingInset: horizontalInset,
                                             trailingInset: horizontalInset,
                                             titleWidth: fixedTitleWidth ?? titleRun.width(),
                                             valueWidth: valueRun.width(),
                                             gap: elementGap,
                                             hasProgress: row.progress != nil,
                                             minBarWidth: minBarWidth,
                                             leadingWidth: iconWidth)
        var cursorX = rect.minX + horizontalInset
        if iconWidth > 0 { cursorX += iconWidth + elementGap }
        if metrics.titleWidth > 0 {
            titleRun.draw(in: CGRect(x: cursorX,
                                     y: rect.minY,
                                     width: metrics.titleWidth,
                                     height: rect.height))
            cursorX += metrics.titleWidth + elementGap
        }
        if metrics.showsBar {
            let barRect = CGRect(x: cursorX,
                                 y: rect.midY - barHeight / 2,
                                 width: metrics.barWidth,
                                 height: barHeight)
            if row.isEmptyBar {
                DrawnInk.outlineBar(in: barRect, color: trackColor)
            } else if let progress = row.progress {
                DrawnInk.progressBar(in: barRect,
                                     progress: progress,
                                     track: trackColor,
                                     fill: row.tone == .warning ? PaneCardStyle.warnInk : barColor)
            }
        }
        if metrics.valueWidth > 0 {
            valueRun.draw(in: CGRect(x: rect.maxX - horizontalInset - metrics.valueWidth,
                                     y: rect.minY,
                                     width: metrics.valueWidth,
                                     height: rect.height),
                          alignment: .right)
        }
    }

    /// 数值语气 → 颜色（与行列表完全同源）
    private func toneColor(_ tone: DrawnRowSpec.Tone) -> NSColor {
        switch tone {
        case .normal: return PaneCardStyle.secondaryText
        case .strong: return PaneCardStyle.primaryText
        case .warning: return PaneCardStyle.warnInk
        }
    }
}
