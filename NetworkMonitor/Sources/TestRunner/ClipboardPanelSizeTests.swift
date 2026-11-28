import Foundation
import NetworkMonitorUI

// MARK: - 面板高度档位（紧凑 / 标准 / 宽松）

/// 高度档位的守门测试 —— 工具条按钮、设置页滑块与默认值三处读同一份口径
///
/// 钉住四件事：
/// 1. 三档高度递增、都落在设置页滑块的合法区间内（越界会被 clampedHeight 夹成两档一样高）；
/// 2. 紧凑档就是几何下限（卡片区刚好一张基准卡），改基准卡高时不用手改档位；
/// 3. 自定义高度按距离归到最近的一档（不做吸附、不回写偏好）；
/// 4. 循环顺序固定 紧凑 → 标准 → 宽松 → 紧凑，且图标 / 文案随档位变化。
func runClipboardPanelSizeTests() {
    print("🧪 Testing clipboard panel size tiers...")
    do {
        let all = ClipboardPanelSize.allCases
        assertEqual(all.count, 3, "三档：紧凑 / 标准 / 宽松")
        assertEqual(all, [.compact, .standard, .roomy], "档位顺序即循环顺序")

        // 高度：递增、落在合法区间内
        assertEqual(ClipboardPanelSize.compact.height, ClipboardPanelLayout.minPanelHeight,
                    "紧凑档 = 几何下限（卡片区刚好一张最矮整卡）")
        assertEqual(ClipboardPanelSize.standard.height, 264, "标准档 264（卡片 227×198，一屏约 6 张）")
        assertEqual(ClipboardPanelSize.roomy.height, 320, "宽松档 320（卡片 291×254，一屏约 5 张）")
        assertEqual(ClipboardPanelSize.standard.height, ClipboardPanelLayout.defaultPanelHeight,
                    "标准档 = 默认高度（两个值同源，不是一个数抄两遍）")
        assertEqual(ClipboardPanelSize.roomy.height > ClipboardPanelSize.standard.height, true,
                    "宽松档比标准档高")
        for size in all {
            assertEqual(size.height >= ClipboardPanelLayout.minPanelHeight, true, "\(size.label)不低于面板下限")
            assertEqual(size.height <= ClipboardPanelLayout.maxPanelHeight, true, "\(size.label)不超过面板上限")
        }
        // 三档两两不同高：同高会让「点一下按钮面板没变」看起来像按钮坏了
        let heights = Set(all.map(\.height))
        assertEqual(heights.count, 3, "三档高度互不相同")

        // 最近档位：自定义高度归到近的那个，不改写偏好
        assertEqual(ClipboardPanelSize.nearest(to: ClipboardPanelSize.standard.height), .standard, "标准高度 → 标准档")
        assertEqual(ClipboardPanelSize.nearest(to: ClipboardPanelSize.compact.height), .compact, "下限高度 → 紧凑档")
        assertEqual(ClipboardPanelSize.nearest(to: ClipboardPanelSize.roomy.height), .roomy, "宽松高度 → 宽松档")
        assertEqual(ClipboardPanelSize.nearest(to: 220), .compact, "220 更靠近紧凑档")
        assertEqual(ClipboardPanelSize.nearest(to: 280), .standard, "280 更靠近标准档（264）")
        assertEqual(ClipboardPanelSize.nearest(to: 310), .roomy, "310 更靠近宽松档（320）")
        assertEqual(ClipboardPanelSize.nearest(to: 480), .roomy, "超出三档的自定义高度归到最近的宽松档")
        assertEqual(ClipboardPanelSize.nearest(to: 0), .standard, "高度缺失 / 0 → 标准档")
        assertEqual(ClipboardPanelSize.nearest(to: -.infinity), .standard, "非有限高度 → 标准档")

        // 循环：紧凑 → 标准 → 宽松 → 紧凑
        assertEqual(ClipboardPanelSize.compact.next, .standard, "紧凑 → 标准")
        assertEqual(ClipboardPanelSize.standard.next, .roomy, "标准 → 宽松")
        assertEqual(ClipboardPanelSize.roomy.next, .compact, "宽松 → 紧凑（环回）")

        // 图标与文案：三档互不相同，且 tooltip 同时说清「现在」与「下一档」
        let symbols = Set(all.map(\.symbolName))
        assertEqual(symbols.count, 3, "三档图标互不相同（看得出来自己在哪一档）")
        for size in all {
            assertEqual(size.switchHint.contains(size.label), true, "\(size.label)的提示含当前档位名")
            assertEqual(size.switchHint.contains(size.next.label), true, "\(size.label)的提示含下一档名")
        }

        print("✅ Clipboard panel size tiers work")
    }
}
