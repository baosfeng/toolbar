import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 位图写进系统剪贴板的唯一出口

/// 截图复制 / 贴图复制共用同一条写入路径
///
/// 为什么不用 `pasteboard.writeObjects([NSImage])`：NSImage 作为剪贴板载体时只提供
/// **未压缩 TIFF** 一种表示——全屏 Retina 截图（3024×1964）实测 22.7 MB，两个后果：
/// 1. 超过剪贴板历史单图上限 `ClipboardLimit.maxImageBytes`（20 MB），采集器整条静默跳过，
///    用户看到的就是「截图复制了，但历史里没有这张图」；
/// 2. 只读 TIFF 的 App 每次粘贴都要解一张 22 MB 的未压缩位图。
///
/// 这里改成「PNG 优先 + 小图补 TIFF」：同尺寸 PNG 实测 40 ms、体积小两个数量级，
/// 其它 App 按 `.png` 优先取即可；TIFF 仍保留一份给只认它的老 App，但超过
/// `tiffCompanionPixelLimit` 就不补——宁可极个别老 App 读不到，也不把 20 MB+ 的
/// 未压缩位图塞进系统剪贴板。
@MainActor
enum SnipPasteboardImageWriter {

    /// 写入剪贴板（先清空）；返回是否写入成功
    @discardableResult
    static func write(_ image: CGImage,
                      to pasteboard: NSPasteboard = .general,
                      logger: LoggingService = AppContext.shared.logger) -> Bool {
        guard let item = makeItem(for: image, logger: logger) else { return false }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            logger.error("写入系统剪贴板失败：图片载体未被接受")
            return false
        }
        return true
    }

    /// 构造剪贴板载体（纯构造函数，测试可脱离系统剪贴板断言表示组合）
    static func makeItem(for image: CGImage,
                         logger: LoggingService = AppContext.shared.logger) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        var representations = 0
        let png = ClipboardImageDecoder.pngData(from: image)
        if let png {
            item.setData(png, forType: .png)
            representations += 1
        }
        if png == nil {
            // PNG 编不出来：TIFF 是唯一出路，此时体积不再是考虑项
            if let tiff = ClipboardImageDecoder.tiffData(from: image) {
                item.setData(tiff, forType: .tiff)
                representations += 1
            } else {
                logger.warning("剪贴板图片：PNG 与 TIFF 两种表示都编码失败")
            }
        } else if SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: image.width, height: image.height) {
            // 小图额外补一份 TIFF，兼容只认 TIFF 的老 App；大图的未压缩 TIFF 不写
            if let tiff = ClipboardImageDecoder.tiffData(from: image) {
                item.setData(tiff, forType: .tiff)
                representations += 1
            }
        }
        guard representations > 0 else { return nil }
        return item
    }
}
