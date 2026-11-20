import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 位图写进系统剪贴板的唯一出口

/// 截图复制 / 贴图复制共用同一条写入路径
///
/// 为什么不用 `pasteboard.writeObjects([NSImage])`：NSImage 作为剪贴板载体只提供
/// **未压缩 TIFF** 一种表示——全屏 Retina 截图（3024×1964）实测 22.7 MB，两个后果：
/// 1. 超过剪贴板历史单图上限 `ClipboardLimit.maxImageBytes`（20 MB），采集器整条静默跳过，
///    用户看到的就是「截图复制了，但历史里没有这张图」；
/// 2. 只读 TIFF 的 App 每次粘贴都要解一张 22 MB 的未压缩位图。
///
/// 现在按 `SnipPasteboardImageBudget` 的体积预算出图（用户口径：1 MB 是上限）：
/// 2x 无损 PNG → 1x 无损 PNG（Retina 屏按点数显示仍是原生清晰度）→ JPEG 0.85 兜底，
/// 取第一个不超预算的档位。实测全屏 3024×1964：2x PNG 1.73MB / 1x PNG 0.69MB /
/// 2x JPEG 0.81MB / 1x JPEG 0.30MB，因此全屏截图稳定落在 1x PNG。
///
/// 不再写 TIFF 伴随表示：LZW 压缩后它与 PNG 同量级（1x 实测 0.77MB），多一份既推高
/// 剪贴板占用又不解决兼容（`public.png` / `public.jpeg` 是系统与绝大多数 App 的通用入口）。
@MainActor
enum SnipPasteboardImageWriter {

    /// JPEG 兜底档的质量（文字截图可接受，照片级画面明显优于再降分辨率）
    static let lossyQuality = 0.85

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

    /// 构造剪贴板载体（按体积预算选档位）
    static func makeItem(for image: CGImage,
                         logger: LoggingService = AppContext.shared.logger) -> NSPasteboardItem? {
        // 1x = 屏幕点数分辨率：最长边减半（Retina 的 2x 图正好回到点数像素）
        let pointSizeImage = ClipboardImageDecoder.thumbnail(
            from: image,
            maxPixelSize: max(image.width, image.height) / 2) ?? image
        var payloads: [Data?] = []
        var oversized: (data: Data, tier: SnipPasteboardImageBudget.Tier)?
        for tier in SnipPasteboardImageBudget.Tier.allCases {
            let source = tier.isDownscaled ? pointSizeImage : image
            let data = encoded(source, tier: tier)
            payloads.append(data)
            if let data, oversized == nil {
                oversized = (data, tier)
            }
        }
        let byteCounts = payloads.map { $0?.count }
        guard let tier = SnipPasteboardImageBudget.firstFittingTier(byteCounts: byteCounts),
              let data = payloads[tier.rawValue] else {
            // 四档全超预算或全编码失败：用第一次成功的编码兜底，至少「有图可粘」
            guard let oversized else {
                logger.warning("剪贴板图片：四个档位全部编码失败")
                return nil
            }
            logger.warning("剪贴板图片仍超出 1MB 预算（\(oversized.data.count) 字节），按 \(tierName(oversized.tier)) 兜底输出")
            return item(data: oversized.data, tier: oversized.tier)
        }
        logger.info("剪贴板图片按 \(tierName(tier)) 输出：\(data.count) 字节（预算 \(SnipPasteboardImageBudget.byteBudget)）")
        return item(data: data, tier: tier)
    }

    // MARK: 内部实现

    private static func encoded(_ image: CGImage, tier: SnipPasteboardImageBudget.Tier) -> Data? {
        switch tier {
        case .png2x, .png1x:
            return ClipboardImageDecoder.pngData(from: image)
        case .jpeg2x, .jpeg1x:
            return ClipboardImageDecoder.jpegData(from: image, compressionQuality: lossyQuality)
        }
    }

    private static func item(data: Data, tier: SnipPasteboardImageBudget.Tier) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: tier.isLossy
                               ? NSPasteboard.PasteboardType(ClipboardImageFormat.jpegTypeName)
                               : .png)
        return pasteboardItem
    }

    private static func tierName(_ tier: SnipPasteboardImageBudget.Tier) -> String {
        switch tier {
        case .png2x: return "2x PNG（无损）"
        case .png1x: return "1x PNG（无损，屏幕点数分辨率）"
        case .jpeg2x: return "2x JPEG \(Int(lossyQuality * 100))%"
        case .jpeg1x: return "1x JPEG \(Int(lossyQuality * 100))%"
        }
    }
}
