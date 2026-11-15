import CoreGraphics

// MARK: - flipped 上下文里的翻正变换（纯逻辑）

/// 翻转坐标系下的翻正变换 —— 纯算术，供自绘原语与 TestRunner 共用
///
/// 背景：自绘视图统一 `isFlipped = true`，而位图绘制（`NSImage.draw(in:from:operation:fraction:)`）
/// 不做坐标补偿（文本绘制自己会翻正，位图不会），直接画会上下颠倒。
/// 翻正做法是在目标矩形中线上做一次纵向镜像 —— 变换取值与「是否需要翻」的判断都在这里，
/// 原语只负责施加，测试可以直接断言变换数值，也可以离屏取样验证像素走向。
public enum DrawnUnflip {

    /// 目标矩形内的翻正变换；上下文本来就不是 flipped 时返回 nil（不需要动）
    ///
    /// - Parameters:
    ///   - rect: 绘制目标矩形（其纵向中线是镜像轴）
    ///   - contextIsFlipped: 当前绘图上下文是否为 flipped
    public static func transform(around rect: CGRect, contextIsFlipped: Bool) -> CGAffineTransform? {
        guard contextIsFlipped, rect.height > 0 else { return nil }
        return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * rect.midY)
    }

    /// 需要翻正吗（视图侧据此决定走哪条绘制路径）
    public static func needsFlip(rect: CGRect, contextIsFlipped: Bool) -> Bool {
        transform(around: rect, contextIsFlipped: contextIsFlipped) != nil
    }
}
