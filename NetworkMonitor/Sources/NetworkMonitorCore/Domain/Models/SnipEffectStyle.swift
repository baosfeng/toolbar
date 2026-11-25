import CoreGraphics
import Foundation

// MARK: - 像素效果的强度（马赛克 / 模糊）

/// 马赛克与高斯模糊的强度 —— 两根独立的旋钮，各自记忆
///
/// Snipaste 明确把两者分开（更新日志 v1.13.5「马赛克与高斯模糊各自独立记忆」），
/// 我们此前两个值都是写死 14（`SnipMosaicProcessor.defaultBlockSize/defaultBlurRadius`），
/// 用户没有任何入口。这里把它们收进标注样式：**每条标注带着自己落笔时的强度**，
/// 这样已经画好的形状不会因为"现在调粗了一点"而整张变样。
public struct SnipEffectStyle: Equatable, Sendable {

    /// 马赛克块边长（像素）；2 以下没有马赛克感，32 以上整块被糊成一色
    public var mosaicBlock: CGFloat
    /// 高斯模糊半径（像素）
    public var blurRadius: CGFloat

    public init(mosaicBlock: CGFloat = SnipEffectStyle.defaultMosaicBlock,
                blurRadius: CGFloat = SnipEffectStyle.defaultBlurRadius) {
        self.mosaicBlock = SnipEffectStyle.clampMosaic(mosaicBlock)
        self.blurRadius = SnipEffectStyle.clampBlur(blurRadius)
    }

    /// 与 `SnipMosaicProcessor` 的既有常量对齐，老标注观感零变化
    public static let defaultMosaicBlock: CGFloat = 14
    public static let defaultBlurRadius: CGFloat = 14

    public static let mosaicRange: ClosedRange<CGFloat> = 2...32
    public static let blurRange: ClosedRange<CGFloat> = 1...40

    public static func clampMosaic(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultMosaicBlock }
        return min(max(value.rounded(), mosaicRange.lowerBound), mosaicRange.upperBound)
    }

    public static func clampBlur(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultBlurRadius }
        return min(max(value.rounded(), blurRange.lowerBound), blurRange.upperBound)
    }
}
