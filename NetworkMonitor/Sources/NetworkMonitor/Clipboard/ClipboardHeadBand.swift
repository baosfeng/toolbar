import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 卡头带（按来源 App 染色）

/// 卡片顶部的来源色头带 —— 独立于整卡绘制的一小块，色值与对比度全部来自
/// SourceAppPalette（纯逻辑、TestRunner 覆盖），这里只做「取色 → 画一条带 + 一行字」。
///
/// 分离成独立文件而不是塞进 ClipboardCardView+Drawing：那是一族已经到棘轮上限的
/// 大文件，来源染色是新增的独立关注点，不该把它的行数再推高。
///
/// 版式（对标 Paste 的彩色卡头，带高 26pt）：
/// 左「类型名」（+ 复制次数，多于一次时才写）→ 右「相对时间」→ 最右「来源 App 图标」。
/// 宽度不够时按「复制次数 → 相对时间」的顺序依次让位，类型名与图标始终保留。
/// 原来面板底部详情区右上角那行「复制 2 次 · 文本 · 6 分钟前 · DeepSeek Harness」就是拆到这里：
/// 类型 / 时间进卡头、来源进卡脚，复制次数进卡头，一行都不丢。
extension ClipboardCardView {

    /// 头带类型名字体（10.5pt semibold：26pt 带高里站得住，又比正文 13pt 低一档）
    static var bandFont: NSFont {
        NSFont.systemFont(ofSize: 10.5, weight: .semibold)
    }

    /// 头带相对时间字体（9.5pt：与类型名拉开层级，单行放得下「3 分钟前」）
    static var bandTimeFont: NSFont {
        NSFont.systemFont(ofSize: 9.5, weight: .regular)
    }

    /// 头带复制次数字体（9pt：比时间再低一档，它是辅助事实不是主语）
    static var bandCountFont: NSFont {
        NSFont.systemFont(ofSize: 9, weight: .regular)
    }

    /// 卡头带：底色取来源 App 主题色，带内写「类型 + 复制次数 + 相对时间 + 来源图标」
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

        let type = DrawnTextRun(string: ClipboardItemKindLabel.label(for: item),
                                font: Self.bandFont, color: ink)
        let minLeft = rect.minX + ClipboardCardGeometry.bandPaddingX
        let typeRight = minLeft + type.exactSize.width

        // 右：「相对时间」贴着图标；宽度不够时先让时间消失，类型名必须完整
        let time = DrawnTextRun(string: ClipboardRelativeTime.string(from: item.createdAt, now: Date()),
                                font: Self.bandTimeFont, color: ink.withAlphaComponent(0.78))
        var textRight = rightX
        if rightX - typeRight - ClipboardCardGeometry.bandGap * 2 >= time.exactSize.width {
            time.draw(at: CGPoint(x: rightX - time.exactSize.width,
                                  y: rect.midY - time.exactSize.height / 2))
            textRight = rightX - time.exactSize.width - ClipboardCardGeometry.bandGap * 2
        }

        // 类型之后：「· 复制 N 次」（只在复制过多次时出现，宽度不够就整段让位）
        if item.copyCount > 1 {
            let count = DrawnTextRun(string: "· 复制 \(item.copyCount) 次",
                                     font: Self.bandCountFont, color: ink.withAlphaComponent(0.72))
            if textRight - typeRight - ClipboardCardGeometry.bandGap >= count.exactSize.width {
                count.draw(at: CGPoint(x: typeRight + ClipboardCardGeometry.bandGap,
                                       y: rect.midY - count.exactSize.height / 2))
            }
        }
        type.draw(at: CGPoint(x: minLeft, y: rect.midY - type.exactSize.height / 2))
    }
}
