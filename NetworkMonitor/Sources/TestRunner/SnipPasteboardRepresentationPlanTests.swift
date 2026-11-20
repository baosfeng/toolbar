import Foundation
import NetworkMonitorUI

// MARK: - 截图复制到剪贴板的表示规划

/// 覆盖：全屏截图不再额外写 22MB 未压缩 TIFF（否则超过历史单图上限、整条采不到）
func runSnipPasteboardRepresentationPlanTests() {
    print("🧪 Testing Snip pasteboard representation plan...")

    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: 1200, height: 800),
                true, "小图补 TIFF（兼容只认 TIFF 的老 App）")
    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: 2000, height: 2000),
                true, "整好 400 万像素仍补 TIFF")
    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: 2001, height: 2000),
                false, "超过 400 万像素只写 PNG")
    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: 3024, height: 1964),
                false, "全屏 Retina 截图不写未压缩 TIFF（约 22MB）")
    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: 0, height: 100),
                true, "尺寸异常交给编码器兜底")
    assertEqual(SnipPasteboardRepresentationPlan.includesTIFFCompanion(width: Int.max, height: 2),
                false, "乘法溢出按不补 TIFF 处理")

    print("✅ Snip pasteboard representation plan works")
}
