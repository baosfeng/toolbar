import AppKit
import NetworkMonitorCore

// MARK: - 卡片静态资源

/// `ClipboardCardView` 的静态资源扩展 — 符号、缩略图、来源 App 图标与等比填充绘制
///
/// 成员声明为 internal 而非 private：由拆出的主文件 `ClipboardCardView.swift` 跨文件调用，
/// 同目录内无其他调用方。缓存本体留在主类内（Swift 扩展不能声明存储属性）。
extension ClipboardCardView {

    /// 类型符号名（正文按 URL / JSON / 命令细分；禁止 emoji）
    static func symbolName(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image: return "photo"
        case .file: return "doc"
        case .rtf: return "textformat"
        case .text:
            let trimmed = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("www.") {
                return "link"
            }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "curlybraces" }
            return ClipboardCardTextStyle.isMonospaced(trimmed) ? "terminal" : "text.alignleft"
        }
    }

    /// SF Symbol 着色图（禁止 emoji，全部使用系统符号）
    static func symbolImage(named name: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return image.withSymbolConfiguration(configuration) ?? image
    }

    /// 缩略图（懒加载 + 按解码字节计费的缓存）
    ///
    /// 只读 <hash>_thumb.png；缩略图缺失时用 ImageIO 从原图降采样补生成（内存与缩略图尺寸成正比）。
    /// 禁止回退整张原图解码：那会把 60–300MB 位图常驻进缓存（本次修复的根因之一）。
    static func thumbnail(for item: ClipboardItem) -> NSImage? {
        let key = item.contentHash as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = ClipboardImageStore.thumbnailURL(for: item.contentHash)
        var cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path)
        if cgImage == nil, let imagePath = item.imagePath,
           ClipboardImageStore.regenerateThumbnail(contentHash: item.contentHash,
                                                    imagePath: imagePath,
                                                    logger: AppContext.shared.logger) {
            cgImage = ClipboardImageDecoder.thumbnail(fromFileAt: url.path)
        }
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height))
        // cost = 解码后像素字节数：缩略图正常 320×320×4 ≈ 400KB，64MB 预算约容 160 张
        let cost = ClipboardImagePolicy.decodedBytes(width: cgImage.width, height: cgImage.height)
        thumbnailCache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// 来源 App 图标（缓存；取不到时返回 nil，右侧只留时间）
    static func applicationIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        let key = bundleID as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        guard let icon = NSImage(contentsOf: url.appendingPathComponent("Contents/Resources/app.icns"))
                ?? NSWorkspace.shared.icon(forFile: url.path) as NSImage? else { return nil }
        icon.size = NSSize(width: 12, height: 12)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    /// 等比填充绘制（铺满目标矩形，超出部分裁剪）
    static func drawAspectFill(image: NSImage, in rect: NSRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawnSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let target = NSRect(x: rect.midX - drawnSize.width / 2,
                            y: rect.midY - drawnSize.height / 2,
                            width: drawnSize.width,
                            height: drawnSize.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// 角标文案：1→①，20 以上回退为数字
    static func badgeText(_ position: Int) -> String {
        let circled = "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
        guard position >= 1, position <= circled.count else { return "\(position)" }
        return String(Array(circled)[position - 1])
    }
}
