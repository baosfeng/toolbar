import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 卡头带（按来源 App 染色）

/// 卡片顶部的来源色头带 —— 独立于整卡绘制的一小块，色值与对比度全部来自
/// `SourceAppPalette`（纯逻辑、TestRunner 覆盖），这里只做「取色 → 画一条带 + 一行字」。
///
/// 分离成独立文件而不是塞进 `ClipboardCardView+Drawing`：那是一族已经到棘轮上限的
/// 大文件，来源染色是新增的独立关注点，不该把它的行数再推高。
///
/// 版式（对标 Paste 的彩色卡头，带高 26pt）：
/// 左「类型名」（链接 / 文本 / 图片…）→ 右「相对时间」→ 最右「来源 App 图标」。
/// 类型从卡内正文区搬到卡头，卡身因此能把整块空间留给内容。
extension ClipboardCardView {

    /// 头带类型名字体（10.5pt semibold：26pt 带高里站得住，又比正文 13pt 低一档）
    static var bandFont: NSFont {
        NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    }

    /// 头带相对时间字体（9.5pt：与类型名拉开层级，单行放得下「3 分钟前」）
    static var bandTimeFont: NSFont {
        NSFont.systemFont(ofSize: 9.5, weight: .regular)
    }

    /// 卡头带：底色取来源 App 主题色，带内写「类型 + 相对时间 + 来源图标」
    ///
    /// 未知来源只画一条中性带底、不写类型与时间：回落色没有「来源语义」，
    /// 但卡头的形状要保住，否则同屏卡片的版式不齐。
    func drawHeadBand(item: ClipboardItem, in bounds: CGRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = SourceAppPalette.tint(bundleID: item.sourceBundleID,
                                         appName: item.sourceAppName, isDark: isDark)
        let rect = ClipboardCardGeometry.headBandRect(in: bounds)
        // 按卡体圆角裁切：头带与卡同宽，只有上两个角跟着卡一起圆
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).addClip()
        DrawnInk.fill(rect, radius: 0, color: tint.color.nsColor)
        NSGraphicsContext.restoreGraphicsState()

        let ink = SourceAppPalette.ink(on: tint.color).color.nsColor
        var rightX = rect.maxX - ClipboardCardGeometry.bandPaddingX

        // 右：来源 App 图标（取不到真图标时留空，不画假字块冒充）
        let iconSide = ClipboardCardGeometry.bandIconSize
        if let icon = Self.applicationIcon(bundleID: item.sourceBundleID) {
            let iconRect = CGRect(x: rightX - iconSide,
                                  y: rect.midY - iconSide / 2,
                                  width: iconSide, height: iconSide)
            // 卡片是 flipped 视图：位图不翻正会上下颠倒（与缩略图同一条路径）
            DrawnInk.withUnflippedIfNeeded(around: iconRect) {
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            rightX -= iconSide + ClipboardCardGeometry.bandGap
        }

        // 右：「相对时间」贴着图标；宽度不够时先让时间消失，类型名必须完整
        let time = DrawnTextRun(string: ClipboardRelativeTime.string(from: item.createdAt, now: Date()),
                                font: Self.bandTimeFont, color: ink.withAlphaComponent(0.78))
        let type = DrawnTextRun(string: ClipboardItemKindLabel.label(for: item),
                                font: Self.bandFont, color: ink)
        let minLeft = rect.minX + ClipboardCardGeometry.bandPaddingX
        let typeRight = minLeft + type.exactSize.width
        let timeWidth = rightX - typeRight - ClipboardCardGeometry.bandGap * 2
        if timeWidth >= time.exactSize.width {
            time.draw(at: CGPoint(x: rightX - time.exactSize.width,
                                  y: rect.midY - time.exactSize.height / 2))
        }
        type.draw(at: CGPoint(x: minLeft, y: rect.midY - type.exactSize.height / 2))
    }
}