import Foundation
import NetworkMonitorUI

// MARK: - 贴图窗滚轮换算（透明度 / 缩放判据）

/// PinScrollAdjustment 的完整契约
///
/// 守的是用户报的那个 bug：「我移动贴图的时候，贴图的透明度还会发生变化，越来越透明了」。
/// 三道闸各有用例：拖动会话中忽略、惯性阶段忽略、步长按设备分档。
func runPinScrollAdjustmentTests() {
    print("🧪 Testing pin scroll adjustment...")

    // 1) 拖动会话中：无论有没有 ⌃、有没有位移，一律 ignore（改前这里会照改透明度）
    for delta in [CGFloat(1), 3, 30, -30] {
        assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: delta, phase: .changed,
                                               momentumPhase: .none,
                                               hasPreciseScrollingDeltas: false,
                                               isControlPressed: true, isDragging: true),
                    .ignore, "拖动会话中 ⌃+滚轮（deltaY=\(delta)）不改透明度")
    }
    // 拖动 N 帧的等价断言：滑过 60 帧滚轮，alpha 一分不变
    var alpha: CGFloat = 0.86
    for _ in 0..<60 {
        guard case .alpha(let d) = PinScrollAdjustment.intent(scrollingDeltaY: 3, phase: .changed,
                                                              momentumPhase: .none,
                                                              hasPreciseScrollingDeltas: false,
                                                              isControlPressed: true,
                                                              isDragging: true)
        else { continue }
        alpha = PinScrollAdjustment.alpha(from: alpha, delta: d)
    }
    assertEqual(alpha, 0.86, "拖动 60 帧后透明度一分不变")

    // 2) 惯性阶段忽略：触控板松手后 momentum 仍连发，改前每帧都改一次透明度
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 20, phase: .changed,
                                           momentumPhase: .began,
                                           hasPreciseScrollingDeltas: true,
                                           isControlPressed: true, isDragging: false),
                .ignore, "惯性阶段不改透明度")
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 20, phase: .changed,
                                           momentumPhase: .changed,
                                           hasPreciseScrollingDeltas: true,
                                           isControlPressed: true, isDragging: false),
                .ignore, "惯性进行中不改透明度")

    // 3) 阶段结束 / 零位移：不改数值
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 10, phase: .ended, momentumPhase: .none,
                                           hasPreciseScrollingDeltas: true,
                                           isControlPressed: true, isDragging: false),
                .ignore, "阶段结束的那一帧不改透明度")
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 0, phase: .changed, momentumPhase: .none,
                                           hasPreciseScrollingDeltas: false,
                                           isControlPressed: true, isDragging: false),
                .ignore, "零位移不改透明度")

    // 4) 正常路径：机械滚轮一格（deltaY=1）⌃ 下透明度 +0.03，与改前同档
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 1, phase: .changed, momentumPhase: .none,
                                           hasPreciseScrollingDeltas: false,
                                           isControlPressed: true, isDragging: false),
                .alpha(0.03), "机械滚轮一格 ⌃ 下透明度 +0.03（保持改前手感）")
    // 触控板同一物理动作是像素级：步长必须小得多，否则一划就归零（改前正是如此）
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 30, phase: .changed, momentumPhase: .none,
                                           hasPreciseScrollingDeltas: true,
                                           isControlPressed: true, isDragging: false),
                .alpha(0.06), "触控板滑 30pt 只改 0.06（改前是 0.9，直接归零）")

    // 5) 缩放：裸滚轮仍是乘法语义，系数与改前一致（0.02）
    assertEqual(PinScrollAdjustment.intent(scrollingDeltaY: 10, phase: .changed, momentumPhase: .none,
                                           hasPreciseScrollingDeltas: false,
                                           isControlPressed: false, isDragging: false),
                .scale(1.2), "机械滚轮 10 格放大 1.2 倍（与改前同档）")

    // 6) 钳制：透明度 0.1…1、缩放 0.1…10
    assertEqual(PinScrollAdjustment.alpha(from: 0.15, delta: -0.5), 0.1, "透明度钳到下限 0.1")
    assertEqual(PinScrollAdjustment.alpha(from: 0.95, delta: 0.5), 1, "透明度钳到上限 1")
    assertEqual(PinScrollAdjustment.scale(from: 9, factor: 2), 10, "缩放钳到上限 10")
    assertEqual(PinScrollAdjustment.scale(from: 0.15, factor: 0.1), 0.1, "缩放钳到下限 0.1")

    // 7) 阶段位映射：AppKit 的阶段是位掩码，多段并存时按终态优先
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 0), .none, "无阶段位 = 非手势滚动")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 1), .began, "began")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 2), .changed, "changed")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 4), .ended, "ended")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 8), .cancelled, "cancelled")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 32), .mayBegin, "mayBegin")
    assertEqual(PinScrollAdjustment.Phase(rawPhaseBits: 2 | 4), .ended, "changed+ended 并存时落终态")

    print("✅ 贴图窗滚轮换算测试通过")
}
