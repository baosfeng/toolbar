import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 卡片卡脚（标题 + 来源两行）

/// 卡片底部卡脚的绘制 —— 独立成文件而不是继续堆进 `ClipboardCardView+Content`：
///
/// 1. 那是已到同族棘轮上限（`Clipboard/ClipboardCardView` 族只允许变小）的一族，
///    卡脚是「三段式卡片」新增的独立关注点，不该把它的行数再推高（与 `ClipboardHeadBand` 同一处理）；
/// 2. 卡脚与卡头是对称的两端（一个是来源色面、一个是白底信息行），放在一起更好改。
///
/// 版式：顶部一条发丝线把卡身与卡脚分开 → 标题行（标题 + 收藏星）→ 来源行（来源 · 体量 + ⌘N）。
/// 文案口径在 `ClipboardFooterText`（纯逻辑，TestRunner 覆盖），这里只管排版与绘制。
extension ClipboardCardView {


    /// 卡脚：顶部发丝线 → 标题行（标题 + 收藏星）→ 来源行（来源 App 图标 + 来源名 / 内容摘要 + ⌘N）
    ///
    /// 对标 Paste 卡脚的「标题 + 域名」两行：标题是这一条的主语（文本取首行、图片取文件名、
    /// 文件取文件名），副标题写「来源 · 体量」，让用户两行内判断「这条要不要」。
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

        // 标题行：⌘N 提示留出右侧位置，标题在剩余宽度内尾部省略
        let shortcut = ClipboardCardGeometry.shortcutText(number: shortcutNumber)
        var titleRight = titleRect.maxX - (shortcut == nil ? 0 : Self.starSize + Self.metaGap)
        if shortcut != nil { titleRight = titleRect.maxX - Self.starSize - Self.metaGap }
        let titleText = ClipboardFooterText.title(for: item)
        DrawnTextBlock(string: titleText,
                       font: Self.footerTitleFont,
                       color: PaneCardStyle.primaryText,
                       lineSpacing: 0,
                       maxLines: 1).draw(topIn: CGRect(x: titleRect.minX, y: titleRect.minY,
                                                       width: max(0, titleRight - titleRect.minX),
                                                       height: titleRect.height))

        // 来源行：左「来源名 · 体量」，右「⌘N」
        var sourceRight = sourceRect.maxX
        if let shortcut {
            let run = DrawnTextRun(string: shortcut, font: Self.metaFont, color: PaneCardStyle.tertiaryText)
            run.draw(at: CGPoint(x: sourceRight - run.exactSize.width,
                                 y: sourceRect.midY - run.exactSize.height / 2))
            sourceRight -= run.exactSize.width + Self.metaGap
        }
        let sourceText = ClipboardFooterText.source(for: item)
        let sourceColor = PaneCardStyle.tertiaryText
        DrawnTextBlock(string: sourceText,
                       font: Self.metaFont,
                       color: sourceColor,
                       lineSpacing: 0,
                       maxLines: 1).draw(topIn: CGRect(x: sourceRect.minX, y: sourceRect.minY,
                                                       width: max(0, sourceRight - sourceRect.minX),
                                                       height: sourceRect.height))
    }

}
