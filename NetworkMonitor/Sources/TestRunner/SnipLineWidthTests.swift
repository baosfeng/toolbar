import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - P0-5 画笔粗细（回归：只能点二级面板换线宽）

func runSnipLineWidthTests() {
    print("🧪 Testing snip line width stepper...")

    typealias Stepper = SnipLineWidthStepper
    assertEqual(Stepper.widths, [2, 4, 8], "档位与二级面板同源")

    // 档位内步进
    assertEqual(Stepper.step(from: 2, by: 1), 4, "2 → 4 加粗")
    assertEqual(Stepper.step(from: 4, by: 1), 8, "4 → 8 加粗")
    assertEqual(Stepper.step(from: 8, by: 1), 8, "已在最粗档不再变粗")
    assertEqual(Stepper.step(from: 8, by: -1), 4, "8 → 4 变细")
    assertEqual(Stepper.step(from: 4, by: -1), 2, "4 → 2 变细")
    assertEqual(Stepper.step(from: 2, by: -1), 2, "已在最细档不再变细")

    // 非档位值（设置页给默认线宽）先落到最近档位再步进
    assertEqual(Stepper.step(from: 1, by: 1), 4, "1 落在最近档位 2，加粗到 4")
    assertEqual(Stepper.step(from: 3, by: 1), 4, "3 落在最近档位 2，加粗到 4")
    assertEqual(Stepper.step(from: 5, by: 1), 8, "5 落在最近档位 4，加粗到 8")
    assertEqual(Stepper.step(from: 100, by: -1), 4, "超上限先落 8 档，再变细到 4")

    // delta 为 0 不动（滚轮抖动不该改样式）
    assertEqual(Stepper.step(from: 4, by: 0), 4, "delta 为 0 不改档位")

    print("✅ 画笔粗细档位测试通过")
}
