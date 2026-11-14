import AppKit
import NetworkMonitorCore

// MARK: - 行前图标绘制

// 从 DrawnRowList+Drawing.swift 拆出：两行式接入行图标列后主绘制文件越过单文件体积门禁。

extension DrawnRowList {

    /// 画行前图标：等比缩放到 iconSize 方框内并居中
    ///
    /// 模板图（SF Symbol 占位）按 `iconTint` 上色后再画 —— 自绘不走
    /// `NSImageView.contentTintColor`，模板图原样画出来会是纯黑块。
    /// 跨文件被单行式绘制调用，故放宽为 internal。
    func drawIcon(_ image: NSImage, at rect: CGRect) {
        let shown = tintedIcon(image)
        let scale = min(rect.width / max(shown.size.width, 1),
                        rect.height / max(shown.size.height, 1))
        let drawRect = CGRect(x: rect.midX - shown.size.width * scale / 2,
                              y: rect.midY - shown.size.height * scale / 2,
                              width: shown.size.width * scale,
                              height: shown.size.height * scale)
        shown.draw(in: drawRect,
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
    }

    /// 模板图标上色（按图标对象缓存，图标由 AppIconProvider 复用，对象身份稳定）
    private func tintedIcon(_ image: NSImage) -> NSImage {
        guard image.isTemplate, let tint = iconTint else { return image }
        let key = ObjectIdentifier(image)
        if let hit = tintedIcons[key] { return hit }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        if tintedIcons.count >= 64 { tintedIcons.removeAll(keepingCapacity: true) }
        tintedIcons[key] = tinted
        return tinted
    }
}