import CoreGraphics
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - P0-1 右键语义分离（回归：画到一半右键会丢整张截图）

func runSnipRightClickTests() {
    print("🧪 Testing snip right click intent...")

    typealias Intent = SnipRightClickIntent

    // 编辑态：只收笔，截图与已有标注都保留
    assertEqual(Intent.outcome(hasDraft: true, isTextEditing: false, hasSelectedAnnotation: false),
                .finishAnnotation, "正在画图时右键只收笔（不取消整次截图）")
    assertEqual(Intent.outcome(hasDraft: false, isTextEditing: true, hasSelectedAnnotation: false),
                .finishAnnotation, "文字输入中右键结束输入")
    assertEqual(Intent.outcome(hasDraft: false, isTextEditing: false, hasSelectedAnnotation: true),
                .finishAnnotation, "有选中标注时右键只取消选中")

    // 非编辑态：中止整次截图（官方「重新设置截屏区域 / 中止截屏」）
    assertEqual(Intent.outcome(hasDraft: false, isTextEditing: false, hasSelectedAnnotation: false),
                .cancelSnip, "非编辑态右键中止截图")

    // 叠加态也归到「收笔」：只要有一处在编辑，就不能丢掉整张截图
    assertEqual(Intent.outcome(hasDraft: true, isTextEditing: true, hasSelectedAnnotation: true),
                .finishAnnotation, "多重编辑态一律收笔")

    print("✅ 右键语义测试通过")
}
