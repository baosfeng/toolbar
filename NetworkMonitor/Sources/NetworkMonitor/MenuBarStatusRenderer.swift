import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏状态条目自绘

/// 状态条目自绘 —— 让「某一项用图标代替文字」能与其余文本混排
///
/// 为什么必须自绘：`NSStatusItem` 的 button 只有一枚 image + 一段 title，
/// 做不到「↓10K ↑792K [图标]7.01亿」这种中间一项是图标的混排。
/// 做法：把整条内容（含 ⚠️ / ⏸ 前缀）画成一张 **template** 图，
/// 系统按菜单栏外观自动反色，深浅色与按下高亮都不用自己处理。
@MainActor
enum MenuBarStatusRenderer {

    /// 一段状态栏内容（按上屏顺序）
    struct Segment {
        let metric: MenuBarMetric
        let text: String
    }

    /// 画一条状态栏内容；没有需要图标化的项时返回 nil（调用方回落到纯文本路径）
    static func image(segments: [Segment],
                      iconMetrics: Set<MenuBarMetric>,
                      prefix: String,
                      separator: String,
                      labelStyle: MenuBarLabelStyle,
                      customLabels: [String: String],
                      fontSize: CGFloat = 13) -> NSImage? {
        guard !iconMetrics.isEmpty else { return nil }
        let attributed = makeAttributed(segments: segments,
                                        iconMetrics: iconMetrics,
                                        prefix: prefix,
                                        separator: separator,
                                        labelStyle: labelStyle,
                                        customLabels: customLabels,
                                        fontSize: fontSize)
        let textSize = attributed.size()
        guard textSize.width > 0 else { return nil }
        // 高度取状态栏可用高度：22 的条里上下各留 2，避免贴边被裁
        let height: CGFloat = 18
        let width = ceil(textSize.width)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int((width * scale).rounded(.up)),
                                         pixelsHigh: Int((height * scale).rounded(.up)),
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // 全黑绘制 + template：颜色交给系统（浅色菜单栏反白、按下再反色）
        NSColor.black.set()
        attributed.draw(at: NSPoint(x: 0, y: (height - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    // MARK: - 组装

    private static func makeAttributed(segments: [Segment],
                                       iconMetrics: Set<MenuBarMetric>,
                                       prefix: String,
                                       separator: String,
                                       labelStyle: MenuBarLabelStyle,
                                       customLabels: [String: String],
                                       fontSize: CGFloat) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let result = NSMutableAttributedString()
        if !prefix.isEmpty {
            result.append(NSAttributedString(string: prefix, attributes: attributes))
        }
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator, attributes: attributes))
            }
            if iconMetrics.contains(segment.metric),
               let symbol = segment.metric.symbolName,
               let value = MenuBarIconLabel.valueOnly(text: segment.text,
                                                      metric: segment.metric,
                                                      style: labelStyle,
                                                      customLabels: customLabels),
               let attachment = iconAttachment(symbol: symbol, fontSize: fontSize) {
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: MenuBarIconLabel.spacedValue(value),
                                                 attributes: attributes))
            } else {
                result.append(NSAttributedString(string: segment.text, attributes: attributes))
            }
        }
        return result
    }

    /// SF Symbol → 文本附件（基线略降 1pt，与数字对齐）
    private static func iconAttachment(symbol: String, fontSize: CGFloat) -> NSTextAttachment? {
        let configuration = NSImage.SymbolConfiguration(pointSize: fontSize - 1, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -1.5, width: image.size.width, height: image.size.height)
        return attachment
    }
}
