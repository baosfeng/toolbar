import Foundation
import NetworkMonitorCore

// MARK: - 选区交互状态机

func runSnipSelectionStateTests() {
    print("🧪 Testing Snip selection state machine...")

    var state = SnipSelectionState()
    assertEqual(state.phase, .idle, "初始为空闲")
    assertEqual(state.selection == nil, true, "空闲时无选区")

    // 拖拽新建
    state.begin(at: CGPoint(x: 10, y: 20))
    assertEqual(state.phase, .dragging, "按下进入拖拽")
    state.drag(to: CGPoint(x: 110, y: 120))
    assertEqual(state.rect, CGRect(x: 10, y: 20, width: 100, height: 100), "拖拽过程矩形跟随")
    state.end()
    assertEqual(state.phase, .selected, "抬起后成立选区")
    assertEqual(state.selection, CGRect(x: 10, y: 20, width: 100, height: 100), "选区可读")

    // 误触：过小选区回到空闲
    var tiny = SnipSelectionState()
    tiny.begin(at: .zero)
    tiny.drag(to: CGPoint(x: 0.4, y: 0.4))
    tiny.end()
    assertEqual(tiny.phase, .idle, "亚像素误触回到空闲")
    assertEqual(tiny.rect, .zero, "误触清空矩形")

    // 反向拖拽
    var reverse = SnipSelectionState()
    reverse.begin(at: CGPoint(x: 200, y: 200))
    reverse.drag(to: CGPoint(x: 100, y: 100))
    reverse.end()
    assertEqual(reverse.selection, CGRect(x: 100, y: 100, width: 100, height: 100), "反向拖拽归一化")

    // 命中判定
    assertEqual(state.hitTest(CGPoint(x: 10, y: 20), handleSize: 8), .topLeft, "命中左上角")
    assertEqual(state.hitTest(CGPoint(x: 110, y: 120), handleSize: 8), .bottomRight, "命中右下角")
    assertEqual(state.hitTest(CGPoint(x: 60, y: 20), handleSize: 8), .top, "命中上边中点")
    assertEqual(state.hitTest(CGPoint(x: 60, y: 70), handleSize: 8), .move, "命中内部为移动")
    assertEqual(state.hitTest(CGPoint(x: 500, y: 500), handleSize: 8) == nil, true, "选区外不命中")

    // 调整：右下角拖大
    state.beginAdjust(.bottomRight, at: CGPoint(x: 110, y: 120))
    state.adjust(to: CGPoint(x: 160, y: 170))
    state.endAdjust()
    assertEqual(state.rect, CGRect(x: 10, y: 20, width: 150, height: 150), "右下角调整")

    // 调整：左上角反向拖过右下角时夹到最小边长
    state.beginAdjust(.topLeft, at: CGPoint(x: 10, y: 20))
    state.adjust(to: CGPoint(x: 400, y: 400))
    state.endAdjust()
    assertEqual(state.rect.width >= state.minimumSide && state.rect.height >= state.minimumSide,
                true, "调整后不小于最小边长")

    // 键盘移动
    var mover = SnipSelectionState()
    mover.begin(at: CGPoint(x: 0, y: 0))
    mover.drag(to: CGPoint(x: 50, y: 50))
    mover.end()
    mover.move(by: CGSize(width: 5, height: -3))
    assertEqual(mover.rect, CGRect(x: 5, y: -3, width: 50, height: 50), "键盘移动整块")

    // 扩缩
    mover.expand(by: 5)
    assertEqual(mover.rect, CGRect(x: 0, y: -8, width: 60, height: 60), "向外扩大四边")
    mover.shrink(by: 10)
    assertEqual(mover.rect, CGRect(x: 10, y: 2, width: 40, height: 40), "向内缩小四边")

    // 重置
    state.reset()
    assertEqual(state.phase, .idle, "重置回空闲")
    assertEqual(state.selection == nil, true, "重置后无选区")
}
