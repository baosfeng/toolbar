import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 自绘交互层纯口径（命中区域 / 悬停目标）

/// L4 交互层两件纯口径的守卫：等步行带命中、区域优先级、悬停目标推进
///
/// 背景：命中与悬停原来写在三处（DrawnRowList 的私有 rowIndex / ClipboardCardHitTest 内联 /
/// SystemCardView 的卡头按钮 contains 判断），抽到 DrawnHitRegions 与 DrawnHoverState 后
/// 这里把「边缘包含 / 空隙排除 / 优先级 / 跨行移动 / exit 归零」逐条钉住。
func runDrawnInteractionTests() {
    print("🧪 Testing drawn interaction primitives (hit regions & hover state)...")

    // MARK: 等步行带：行高 28 + 行距 0

    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 0),
                                          bandHeight: 28, step: 28, count: 3), 0,
                "行首（y=0）命中第 0 行")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 27.9),
                                          bandHeight: 28, step: 28, count: 3), 0,
                "行内下边缘之前仍命中第 0 行")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 28),
                                          bandHeight: 28, step: 28, count: 3), 1,
                "行分界线上算下一行（下边缘不含）")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 83.9),
                                          bandHeight: 28, step: 28, count: 3), 2,
                "最后一行内（y=83.9）命中第 2 行")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 84),
                                          bandHeight: 28, step: 28, count: 3), nil,
                "越过最后一行（3 × 28 = 84）不命中")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: -0.1),
                                          bandHeight: 28, step: 28, count: 3), nil,
                "视图上方不命中")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 0),
                                          bandHeight: 28, step: 28, count: 0), nil,
                "没有行时一律不命中")

    // MARK: 等步行带：行高 28 + 行距 2（落在空隙不算命中）

    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 28),
                                          bandHeight: 28, step: 30, count: 3), 0,
                "行距 2 时行下边缘（含）仍命中本行")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 29),
                                          bandHeight: 28, step: 30, count: 3), nil,
                "落在 2pt 行间空隙不命中")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 30),
                                          bandHeight: 28, step: 30, count: 3), 1,
                "步进 30 的第 1 行从 y=30 开始")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 88),
                                          bandHeight: 28, step: 30, count: 3), 2,
                "第 2 行 [60…88] 的下边缘仍命中")
    assertEqual(DrawnHitRegions.bandIndex(at: CGPoint(x: 40, y: 89),
                                          bandHeight: 28, step: 30, count: 3), nil,
                "y=89 落在第 2 行之后的空隙")

    // MARK: 区域优先级（卡头按钮压在整卡上）

    let card = CGRect(x: 0, y: 0, width: 296, height: 120)
    let headAction = CGRect(x: 240, y: 4, width: 50, height: 16)
    let regions = [headAction, card]
    assertEqual(DrawnHitRegions.priorityIndex(at: CGPoint(x: 250, y: 10), in: regions), 0,
                "重叠处取靠前的区域（卡头按钮优先于整卡）")
    assertEqual(DrawnHitRegions.priorityIndex(at: CGPoint(x: 100, y: 60), in: regions), 1,
                "按钮之外落到整卡")
    assertEqual(DrawnHitRegions.priorityIndex(at: CGPoint(x: 300, y: 60), in: regions), nil,
                "卡片之外不命中任何区域")
    assertEqual(DrawnHitRegions.priorityIndex(at: CGPoint(x: 250, y: 10), in: [.zero, card]), 1,
                "空矩形（.zero）不参与命中")
    assertEqual(DrawnHitRegions.priorityIndex(at: CGPoint(x: 250, y: 10), in: []), nil,
                "没有区域时不命中")

    // MARK: 单矩形命中

    assertEqual(DrawnHitRegions.contains(CGPoint(x: 0, y: 0), in: card), true,
                "单矩形命中左上角")
    assertEqual(DrawnHitRegions.contains(CGPoint(x: 295.9, y: 119.9), in: card), true,
                "单矩形命中右下角内侧")
    // CGRect.contains 是半开区间：右 / 下边界不算命中（与 AppKit 的视图命中同一口径）
    assertEqual(DrawnHitRegions.contains(CGPoint(x: 296, y: 120), in: card), false,
                "右 / 下边界不命中（半开区间）")
    assertEqual(DrawnHitRegions.contains(CGPoint(x: 0, y: 0), in: .zero), false,
                "空矩形不命中任何点")

    // MARK: 悬停目标推进

    var hover = DrawnHoverState()
    assertEqual(hover.isHovering, false, "初始无悬停目标")
    assertEqual(hover.blendTarget, 0, "无悬停时过渡目标值为 0")
    assertEqual(hover.move(to: 0), .entered(0), "进入第 0 行")
    assertEqual(hover.target, 0, "目标 = 0")
    assertEqual(hover.blendTarget, 1, "有悬停时过渡目标值为 1")
    assertEqual(hover.move(to: 0), .none, "同一行再移动不产生变化（不重绘）")
    assertEqual(hover.move(to: 1), .moved(from: 0, to: 1), "跨行移动报告 from/to")
    assertEqual(hover.target, 1, "跨行后目标 = 1")
    assertEqual(hover.move(to: nil), .left(1), "移到行间空隙 = 离开目标")
    assertEqual(hover.target, nil, "离开后目标归零")
    assertEqual(hover.blendTarget, 0, "离开后过渡目标值归 0")

    // exit 归零：从有目标直接出视图
    hover.move(to: 2)
    assertEqual(hover.exit(), .left(2), "exit 报告被离开的目标")
    assertEqual(hover.target, nil, "exit 后目标归零")
    assertEqual(hover.exit(), .none, "已无目标时 exit 不产生变化")

    // 越界归零：行数变短后悬停目标不能停在旧行上
    hover.move(to: 4)
    assertEqual(hover.clamp(count: 8), .none, "目标仍在范围内时 clamp 不动")
    assertEqual(hover.target, 4, "范围内目标保持")
    assertEqual(hover.clamp(count: 3), .left(4), "目标越界时 clamp 归零")
    assertEqual(hover.target, nil, "越界归零后无目标")
    assertEqual(hover.clamp(count: 0), .none, "本来就无目标时 clamp 不产生变化")

    // Change 语义：只有真的变了才需要重绘
    assertEqual(DrawnHoverState.Change.none.isChanged, false, "none 不需要重绘")
    assertEqual(DrawnHoverState.Change.entered(3).isChanged, true, "entered 需要重绘")
    assertEqual(DrawnHoverState.Change.left(3).isChanged, true, "left 需要重绘")
    assertEqual(DrawnHoverState.Change.moved(from: 1, to: 2).isChanged, true, "moved 需要重绘")
}
