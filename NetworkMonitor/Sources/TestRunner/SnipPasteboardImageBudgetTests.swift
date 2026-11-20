import Foundation
import NetworkMonitorUI

// MARK: - 截图复制到剪贴板的体积预算

/// 覆盖：全屏截图不再写 1.7MB 无损 PNG（用户口径「1MB 是上限」）——
/// 2x 超预算时降到 1x 无损，仍超才走 JPEG 兜底
func runSnipPasteboardImageBudgetTests() {
    print("🧪 Testing Snip pasteboard image budget...")

    assertEqual(SnipPasteboardImageBudget.byteBudget, 1_048_576, "预算 1MB")

    // 1) 2x 无损就在预算内（小选区）：直接用它，不降分辨率也不有损
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [500_000, 120_000, 300_000, 80_000]), .png2x,
        "2x PNG 不超预算就用 2x")
    // 2) 2x 超预算、1x 达标：降分辨率保无损
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [1_730_000, 690_000, 810_000, 300_000]), .png1x,
        "2x 超预算时降到 1x PNG（全屏截图的实测值）")
    // 3) 两个无损档都超：走 JPEG
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [2_000_000, 1_200_000, 810_000, 300_000]), .jpeg2x,
        "无损档都超预算时走 2x JPEG")
    // 4) 只有 1x JPEG 达标
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [2_000_000, 1_200_000, 1_100_000, 300_000]), .jpeg1x,
        "只剩 1x JPEG 达标时用它")
    // 5) 全部超预算：交给调用方兜底
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [9_000_000, 9_000_000, 9_000_000, 9_000_000]) == nil, true,
        "全部超预算返回 nil")
    // 6) 编码失败的档位跳过
    assertEqual(SnipPasteboardImageBudget.firstFittingTier(
        byteCounts: [nil, 690_000]), .png1x,
        "编码失败的档位被跳过")

    // 7) 档位属性：降采样 / 有损
    assertEqual(SnipPasteboardImageBudget.Tier.png1x.isDownscaled, true, "1x 档按点数降采样")
    assertEqual(SnipPasteboardImageBudget.Tier.png2x.isDownscaled, false, "2x 档不降采样")
    assertEqual(SnipPasteboardImageBudget.Tier.jpeg2x.isLossy, true, "JPEG 档有损")
    assertEqual(SnipPasteboardImageBudget.Tier.png2x.isLossy, false, "PNG 档无损")
    assertEqual(SnipPasteboardImageBudget.Tier.allCases.count, 4, "四档候选")

    print("✅ Snip pasteboard image budget works")
}
