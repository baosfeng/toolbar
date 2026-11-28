import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 卡片卡脚（标题 + 来源两行）

/// 卡片底部卡脚的绘制 —— 独立成文件而不是继续堆进 ClipboardCardView+Content：
///
/// 1. 那是已到同族棘轮上限（Clipboard/ClipboardCardView 族只允许变小）的一族，
///    卡脚是「三段式卡片」新增的独立关注点，不该把它的行数再推高（与 ClipboardHeadBand 同一处理）；
/// 2. 卡脚与卡头是对称的两端（一个是来源色面、一个是白底信息行），放在一起更好改。
///
/// 版式（对标 Paste 的「标题 + 域名」两元素）：顶部一条发丝线 → 标题行 → 来源行。
/// 收藏星与 ⌘N 角标不再常驻：星只在已收藏 / hover / 选中时出现，⌘N 只在 hover / 选中时出现
/// —— 静止态一张卡只有「标题 + 来源」两样东西，与 Paste 的信息密度同档。
extension ClipboardCardView {

    /// 卡脚：顶部发丝线 → 标题行（标题 + 条件收藏星）→ 来源行（来源 · 体量 + 条件 ⌘N）
    ///
    /// 条件显示的两个元素都**预留位置**（星占星宽、⌘N 占定宽），hover 进出时标题与来源文字不重排。
    func drawFooter(item: ClipboardItem, in bounds: CGRect) {
        let footer = ClipboardCardGeometry.footerRect(in: bounds)
        let titleRect = ClipboardCardGeometry.footerTitleRect(in: bounds)
        let sourceRect = ClipboardCardGeometry.footerSourceRect(in: bounds)

        // 顶部发丝线：卡身与卡脚的分界（Paste 的卡脚是白底，靠这条线把它与卡身分开）
        DrawnInk.fill(CGRect(x: footer.minX + ClipboardCardGeometry.Metrics.standard.padding,
                             y: footer.minY,
                             width: max(0, footer.width - ClipboardCardGeometry.Metrics.standard.padding * 2),
                             height: 1),
                      radius: 0,
                      color: PaneCardStyle.hairline.withAlphaComponent(Self.footerHairlineAlpha))

        // 标题行：收藏星出现时让出它的位置（静止态标题吃满整行）
        let starVisible = Self.showsStar(item: item, hovering: isHovering, selected: isSelected)
        let titleRight = titleRect.maxX - (starVisible ? Self.starSize + Self.metaGap : 0)
        DrawnTextBlock(string: ClipboardFooterText.title(for: item),
                       font: Self.footerTitleFont,
                       color: PaneCardStyle.primaryText,
                       lineSpacing: 0,
                       maxLines: 1).draw(topIn: CGRect(x: titleRect.minX, y: titleRect.minY,
                                                       width: max(0, titleRight - titleRect.minX),
                                                       height: titleRect.height))

        // 来源行：左侧「来源名 · 体量」，右侧 ⌘N（悬停 / 选中才画，但位置恒预留）
        let shortcut = ClipboardCardGeometry.shortcutText(number: shortcutNumber)
        let shortcutVisible = shortcut != nil && (isSelected || isHovering)
        if shortcutVisible, let shortcut {
            let run = DrawnTextRun(string: shortcut, font: Self.metaFont, color: PaneCardStyle.tertiaryText)
            run.draw(at: CGPoint(x: sourceRect.maxX - run.exactSize.width,
                                 y: sourceRect.midY - run.exactSize.height / 2))
        }
        DrawnTextBlock(string: ClipboardFooterText.source(for: item),
                       font: Self.metaFont,
                       color: PaneCardStyle.tertiaryText,
                       lineSpacing: 0,
                       maxLines: 1).draw(topIn: CGRect(x: sourceRect.minX, y: sourceRect.minY,
                                                       width: max(0, sourceRect.width - Self.shortcutReserveWidth),
                                                       height: sourceRect.height))
    }

    /// 收藏星是否出现：已收藏常显，其余只在 hover 或选中时出现（Paste 的卡面没有常驻收藏标）
    static func showsStar(item: ClipboardItem, hovering: Bool, selected: Bool) -> Bool {
        item.isPinned || hovering || selected
    }
}
