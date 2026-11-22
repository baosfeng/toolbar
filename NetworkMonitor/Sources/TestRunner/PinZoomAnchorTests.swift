import CoreGraphics
import Foundation
import NetworkMonitorUI

// MARK: - 贴图滚轮缩放锚点

/// PinZoomAnchor 的完整契约：以鼠标为锚时，锚点下的内容点缩放前后不动
///
/// 判据统一用「锚点在窗口内的归一化位置不变」：锚点相对窗口左上角跑掉的量
/// 不超过 0.5pt（换算成归一化比例就是 0.5 / 边长）。
func runPinZoomAnchorTests() {
    print("🧪 Testing pin zoom anchor...")

    // 一个 400×300 的窗口，原点不在 (0,0) 上（屏幕坐标才有意义）
    let frame = CGRect(x: 120, y: 240, width: 400, height: 300)

    // MARK: 以鼠标为锚：放大 / 缩小后锚点归一化位置不变

    let anchors = [
        CGPoint(x: 120, y: 240),            // 左上角
        CGPoint(x: 320, y: 390),            // 正中
        CGPoint(x: 520, y: 540),            // 右下角
        CGPoint(x: 180, y: 500),            // 左下角
        CGPoint(x: 410, y: 260)             // 右上角附近
    ]
    for anchor in anchors {
        let before = PinZoomAnchor.normalized(anchor, in: frame)
        for factor in [2.0, 0.5, 1.25, 0.8] as [CGFloat] {
            let newSize = CGSize(width: frame.width * factor, height: frame.height * factor)
            let origin = PinZoomAnchor.origin(frame: frame, newSize: newSize, anchor: anchor)
            let zoomed = CGRect(origin: origin, size: newSize)
            let after = PinZoomAnchor.normalized(anchor, in: zoomed)
            // 归一化位置差换算回点：× 新窗口边长，必须落在 0.5pt 以内
            let dx = abs(after.x - before.x) * newSize.width
            let dy = abs(after.y - before.y) * newSize.height
            assertEqual(dx <= 0.5 && dy <= 0.5, true,
                        "锚点 \(anchor) 在 ×\(factor) 后仍压在同一个内容点上（偏差 \(dx)/\(dy)pt）")
        }
    }

    // MARK: 键盘 +/- 与缩略图：锚点为 nil 时与旧实现（以中心缩放）逐点等价

    let legacyCenter = CGPoint(x: frame.midX, y: frame.midY)
    for factor in [2.0, 0.5, 1.2, 1 / 1.2] as [CGFloat] {
        let newSize = CGSize(width: frame.width * factor, height: frame.height * factor)
        let expected = CGPoint(x: legacyCenter.x - newSize.width / 2,
                               y: legacyCenter.y - newSize.height / 2)
        assertEqual(PinZoomAnchor.origin(frame: frame, newSize: newSize), expected,
                    "锚点为 nil 时按窗口中心缩放，与旧实现一致（×\(factor)）")
        assertEqual(PinZoomAnchor.origin(frame: frame, newSize: newSize, anchor: legacyCenter),
                    expected, "显式传中心锚点时与缺省锚点同结果")
    }

    // MARK: 边界：锚点超出窗口时夹回窗口内

    let outside = CGPoint(x: frame.maxX + 500, y: frame.minY - 500)
    assertEqual(PinZoomAnchor.clamped(outside, in: frame),
                CGPoint(x: frame.maxX, y: frame.minY),
                "窗口外的鼠标位置夹到窗口右下 / 左上边界")
    let clampedOrigin = PinZoomAnchor.origin(frame: frame,
                                             newSize: CGSize(width: 800, height: 600),
                                             anchor: outside)
    assertEqual(clampedOrigin, CGPoint(x: frame.maxX - 800, y: frame.minY),
                "锚点夹回后按夹后的点换算：右下角固定，窗口向左下扩张")

    // 锚点恰好落在窗口边界上也成立（不因开闭区间抖动）
    for anchor in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.midY)] {
        let before = PinZoomAnchor.normalized(anchor, in: frame)
        let newSize = CGSize(width: 200, height: 150)
        let zoomed = CGRect(origin: PinZoomAnchor.origin(frame: frame, newSize: newSize, anchor: anchor),
                            size: newSize)
        let after = PinZoomAnchor.normalized(anchor, in: zoomed)
        assertEqual(abs(after.x - before.x) * newSize.width <= 0.5
                    && abs(after.y - before.y) * newSize.height <= 0.5, true,
                    "边界锚点 \(anchor) 同样保持不动")
    }

    // MARK: 退化输入：零尺寸窗口不崩、归一化回落 0.5

    let zero = CGRect(x: 0, y: 0, width: 0, height: 0)
    assertEqual(PinZoomAnchor.normalized(CGPoint(x: 0, y: 0), in: zero),
                CGPoint(x: 0.5, y: 0.5), "零尺寸窗口归一化回落 0.5")
    assertEqual(PinZoomAnchor.clamped(CGPoint(x: 10, y: 10), in: zero),
                PinZoomAnchor.center(of: zero), "零尺寸窗口的锚点回落中心")
    assertEqual(PinZoomAnchor.center(of: frame), CGPoint(x: 320, y: 390), "中心锚点就是 midX/midY")

    // MARK: 缩放比钳制口径不变（0.1…10 仍由 PinWindow.setScale 负责，这里守住锚点不破坏它）

    // 极小 / 极大的新尺寸都不产生 NaN / 无穷（贴图窗把它们交给 setFrame 前必须有限）
    for factor in [0.001, 1000.0] as [CGFloat] {
        let newSize = CGSize(width: frame.width * factor, height: frame.height * factor)
        let origin = PinZoomAnchor.origin(frame: frame, newSize: newSize, anchor: CGPoint(x: 300, y: 400))
        assertEqual(origin.x.isFinite && origin.y.isFinite, true,
                    "×\(factor) 的原点仍是有限值，不会把窗口甩到无穷远")
    }

    print("✅ 贴图缩放锚点测试通过")
}
