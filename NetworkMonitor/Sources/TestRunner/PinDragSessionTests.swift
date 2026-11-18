import Foundation
import NetworkMonitorUI

// MARK: - 贴图窗拖动会话（位移计算 + 阈值）

/// PinDragSession 的完整契约
///
/// 拖动已改为「自己算位移」：按下记起点（窗口原点 + 鼠标全局位置），
/// 拖动时按鼠标位移平移窗口。这里守着三条：位移可加、丢帧不累积误差、阈值内不乱挪。
func runPinDragSessionTests() {
    print("🧪 Testing pin drag session...")

    let session = PinDragSession(startOrigin: CGPoint(x: 100, y: 200),
                                 startMouse: CGPoint(x: 500, y: 600))

    // 鼠标没动时窗口也不动（按下后原地松手 == 单击，位置必须一模一样）
    assertEqual(session.origin(forMouse: CGPoint(x: 500, y: 600)), CGPoint(x: 100, y: 200),
                "鼠标未移动时窗口原点不变")

    // 位移按「当前鼠标 − 按下鼠标」直接加在起始原点上
    assertEqual(session.origin(forMouse: CGPoint(x: 640, y: 690)), CGPoint(x: 240, y: 290),
                "拖动位移直接加在起始原点上")
    assertEqual(session.origin(forMouse: CGPoint(x: 340, y: 480)), CGPoint(x: -60, y: 80),
                "反方向拖动同样生效（不夹取，交给系统边界处理）")
    // 同一会话里多次调用互不影响（无状态累加 = 丢帧也不会积累误差）
    assertEqual(session.origin(forMouse: CGPoint(x: 600, y: 650)), CGPoint(x: 200, y: 250),
                "多次取原点结果一致（位移不累加）")
    assertEqual(session.origin(forMouse: CGPoint(x: 600, y: 650)), CGPoint(x: 200, y: 250),
                "重复调用同一鼠标位置得到同一结果")

    // 阈值：小于 3pt 视为单击，不挪窗口（手抖不该把贴图挪走半像素）
    assertEqual(session.isDragBeyondThreshold(mouse: CGPoint(x: 501, y: 600)), false,
                "1pt 位移在阈值内，按单击处理")
    assertEqual(session.isDragBeyondThreshold(mouse: CGPoint(x: 500, y: 602)), false,
                "纵向 2pt 仍在阈值内")
    assertEqual(session.isDragBeyondThreshold(mouse: CGPoint(x: 500, y: 603)), true,
                "纵向 3pt 越过阈值，开始拖动")
    assertEqual(session.isDragBeyondThreshold(mouse: CGPoint(x: 497, y: 600)), true,
                "反方向 3pt 同样越过阈值")
    assertEqual(session.isDragBeyondThreshold(mouse: CGPoint(x: 500, y: 600), threshold: 0), true,
                "阈值为 0 时任何鼠标位置都算拖动（口径可配）")

    // 起点不同时不串味：两个会话各算各的
    let another = PinDragSession(startOrigin: .zero, startMouse: CGPoint(x: 10, y: 10))
    assertEqual(another.origin(forMouse: CGPoint(x: 30, y: 40)), CGPoint(x: 20, y: 30),
                "另一个会话从自己的起点算位移")
    assertEqual(session.origin(forMouse: CGPoint(x: 30, y: 40)), CGPoint(x: -370, y: -360),
                "前一个会话不受影响")

    print("✅ 贴图窗拖动会话测试通过")
}
