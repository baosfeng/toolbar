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

// MARK: - 翻正变换（纯算术 + 离屏取样）

/// flipped 上下文里位图翻正的守卫
///
/// 背景：剪贴板卡片是 \`isFlipped = true\` 的自绘视图，\`NSImage.draw(in:from:operation:fraction:)\`
/// 不做坐标补偿（\`draw(in:)\` 与文字绘制会自己翻正），缩略图因此上下颠倒。
/// 判定与镜像轴取值收敛到 \`DrawnUnflip\`，这里既断言变换数值，也在离屏上下文里真的画一次、
/// 取样像素行来证明「翻正后图的上缘落在矩形的上缘」。
func runDrawnUnflipTests() {
    print("🧪 Testing drawn unflip transform (flipped bitmap drawing)...")

    let rect = CGRect(x: 10, y: 20, width: 40, height: 30)

    // MARK: 变换取值

    assertEqual(DrawnUnflip.needsFlip(rect: rect, contextIsFlipped: true), true,
                "flipped 上下文需要翻正")
    assertEqual(DrawnUnflip.needsFlip(rect: rect, contextIsFlipped: false), false,
                "非 flipped 上下文不需要翻正（文本绘制自己会翻）")
    assertEqual(DrawnUnflip.needsFlip(rect: CGRect(x: 10, y: 20, width: 40, height: 0), contextIsFlipped: true),
                false, "零高矩形不翻（没有可镜像的内容）")

    guard let transform = DrawnUnflip.transform(around: rect, contextIsFlipped: true) else {
        assertEqual(false, true, "flipped 上下文必须给出翻正变换")
        return
    }
    assertEqual(transform.a, 1, "水平方向不缩放")
    assertEqual(transform.b, 0, "不斜切")
    assertEqual(transform.c, 0, "不斜切")
    assertEqual(transform.d, -1, "纵向镜像")
    assertEqual(transform.tx, 0, "不倒平移")
    assertEqual(transform.ty, 2 * rect.midY, "镜像轴落在矩形纵向中线（ty = 2 × midY）")

    // 矩形的上下边互换：矩形自身是镜像轴，翻正后边界不变
    let topLeft = CGPoint(x: rect.minX, y: rect.minY).applying(transform)
    let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY).applying(transform)
    assertEqual(abs(topLeft.y - rect.maxY) < 0.001, true, "上边翻到下边")
    assertEqual(abs(bottomRight.y - rect.minY) < 0.001, true, "下边翻到上边")
    assertEqual(topLeft.x, rect.minX, "左右边界翻转后不变")

    // MARK: 离屏取样：翻正后图的上缘落在矩形上缘

    guard let source = makeTopRedBottomBlueImage() else {
        assertEqual(false, true, "造源图失败")
        return
    }
    let target = CGRect(x: 0, y: 0, width: 40, height: 40)

    func render(applyUnflip: Bool) -> [UInt8]? {
        guard let ctx = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8,
                                  bytesPerRow: 40 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 与 NSView(isFlipped = true) 等价的用户空间：原点在左上、y 向下
        ctx.translateBy(x: 0, y: 40)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        if applyUnflip, let flip = DrawnUnflip.transform(around: target, contextIsFlipped: true) {
            ctx.saveGState()
            ctx.concatenate(flip)
            ctx.draw(source, in: target)
            ctx.restoreGState()
        } else {
            ctx.draw(source, in: target)
        }
        guard let base = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: 40 * 40 * 4))
    }

    /// 取第 row 行（0 = 视觉顶部）的 RGB
    func pixel(_ buffer: [UInt8], row: Int) -> (r: Int, g: Int, b: Int) {
        let offset = row * 40 * 4
        return (Int(buffer[offset]), Int(buffer[offset + 1]), Int(buffer[offset + 2]))
    }

    guard let flipped = render(applyUnflip: true), let plain = render(applyUnflip: false) else {
        assertEqual(false, true, "离屏渲染失败")
        return
    }
    let flippedTop = pixel(flipped, row: 5), flippedBottom = pixel(flipped, row: 34)
    let plainTop = pixel(plain, row: 5), plainBottom = pixel(plain, row: 34)

    assertEqual(flippedTop.r > 200 && flippedTop.b < 60, true,
                "翻正后矩形上缘是源图的上缘（红）")
    assertEqual(flippedBottom.b > 200 && flippedBottom.r < 60, true,
                "翻正后矩形下缘是源图的下缘（蓝）")
    assertEqual(plainTop.b > 200 && plainTop.r < 60, true,
                "不翻正时上缘是源图下缘（蓝）—— 这就是「图片反过来」的成因")
    assertEqual(plainBottom.r > 200 && plainBottom.b < 60, true,
                "不翻正时下缘是源图上缘（红）")
    assertEqual(plainTop.r != flippedTop.r, true, "翻正确实改变了像素走向")

    print("✅ Drawn unflip transform works")
}

/// 造一张「上半红、下半蓝」的 2×2 源图（标准用户空间：y 大 = 上）
private func makeTopRedBottomBlueImage() -> CGImage? {
    guard let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                              bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
    return ctx.makeImage()
}
