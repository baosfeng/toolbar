import AppKit
import NetworkMonitorCore

// MARK: - 剪贴板内容转图像

/// 把剪贴板内容画成可贴到屏幕的图 — 文字、文件、颜色、HTML 四种
@MainActor
enum SnipClipboardRenderer {

    /// 文字贴图的最大宽度（点）
    static let maximumTextWidth: CGFloat = 480

    static func render(_ content: SnipClipboardContent) -> (image: CGImage, size: NSSize)? {
        switch content {
        case .text(let text):
            return renderText(text)
        case .files(let paths):
            return renderFiles(paths)
        case .color(let color):
            return renderColor(color)
        case .html(let html):
            return renderHTML(html)
        case .image:
            return nil
        }
    }

    // MARK: - 文字

    private static func renderText(_ text: String) -> (CGImage, NSSize)? {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle()
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounding = attributed.boundingRect(with: NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        let contentSize = NSSize(width: min(ceil(bounding.width), maximumTextWidth),
                                 height: ceil(bounding.height))
        let size = NSSize(width: contentSize.width + 24, height: contentSize.height + 20)
        return makeImage(size: size, background: .white) { rect in
            attributed.draw(with: NSRect(x: 12, y: 10,
                                         width: contentSize.width,
                                         height: contentSize.height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    // MARK: - 文件

    private static func renderFiles(_ paths: [String]) -> (CGImage, NSSize)? {
        let rows = paths.prefix(8).map { path -> (NSImage, String) in
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 32, height: 32)
            return (icon, (path as NSString).lastPathComponent)
        }
        guard !rows.isEmpty else { return nil }
        let rowHeight: CGFloat = 42
        let width: CGFloat = 320
        let size = NSSize(width: width, height: CGFloat(rows.count) * rowHeight + 16)
        return makeImage(size: size, background: NSColor.white) { _ in
            for (index, row) in rows.enumerated() {
                let top = 8 + CGFloat(index) * rowHeight
                row.0.draw(in: NSRect(x: 12, y: size.height - top - 32, width: 32, height: 32),
                           from: .zero, operation: .sourceOver, fraction: 1)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.black
                ]
                let name = row.1 as NSString
                let nameSize = name.size(withAttributes: attributes)
                name.draw(at: NSPoint(x: 54, y: size.height - top - min(32, nameSize.height) + 4),
                          withAttributes: attributes)
            }
        }
    }

    // MARK: - 颜色

    private static func renderColor(_ color: SnipPixelColor) -> (CGImage, NSSize)? {
        let size = NSSize(width: 150, height: 96)
        let fill = NSColor(srgbRed: CGFloat(color.red) / 255,
                           green: CGFloat(color.green) / 255,
                           blue: CGFloat(color.blue) / 255,
                           alpha: 1)
        let luminance = (Double(color.red) * 0.299 + Double(color.green) * 0.587 + Double(color.blue) * 0.114) / 255
        let textColor: NSColor = luminance > 0.6 ? .black : .white
        return makeImage(size: size, background: fill) { rect in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: textColor
            ]
            let label = color.hexString as NSString
            label.draw(at: NSPoint(x: 12, y: 10), withAttributes: attributes)
        }
    }

    // MARK: - HTML

    private static func renderHTML(_ html: String) -> (CGImage, NSSize)? {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data,
                                                       options: [.documentType: NSAttributedString.DocumentType.html,
                                                                 .characterEncoding: String.Encoding.utf8.rawValue],
                                                       documentAttributes: nil) else {
            return nil
        }
        let plain = attributed.string
        // HTML 渲染太重，正文为空时直接回落纯文本
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let bounding = attributed.boundingRect(with: NSSize(width: maximumTextWidth, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading])
        let contentSize = NSSize(width: min(ceil(bounding.width), maximumTextWidth),
                                 height: ceil(bounding.height))
        let size = NSSize(width: contentSize.width + 24, height: contentSize.height + 20)
        return makeImage(size: size, background: .white) { rect in
            attributed.draw(with: NSRect(x: 12, y: 10,
                                         width: contentSize.width,
                                         height: contentSize.height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    // MARK: - 工具

    private static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = 2
        return style
    }

    private static func makeImage(size: NSSize,
                                  background: NSColor,
                                  draw: (NSRect) -> Void) -> (CGImage, NSSize)? {
        let image = NSImage(size: size)
        image.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: size).fill()
        draw(NSRect(origin: .zero, size: size))
        image.unlockFocus()
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return (cgImage, size)
    }
}
