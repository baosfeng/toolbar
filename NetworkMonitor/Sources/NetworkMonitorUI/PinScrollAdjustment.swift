import Foundation
import CoreGraphics

// MARK: - 贴图窗滚轮换算（纯逻辑，可单测）

/// 贴图窗一次滚轮该把「缩放」或「透明度」改成多少 —— 判据全在这里，视图只落副作用
///
/// 为什么必须收口：改前 `PinWindow.scrollWheel` 直接写
/// `adjustAlpha(by: event.scrollingDeltaY * 0.03)`，三条缺陷都出在这一行——
/// 1. **吞掉所有滚动事件**：不判 `phase` / `momentumPhase`，触控板松手后的惯性阶段照样逐帧调；
/// 2. **拖动中不设闸**：拖动时被带出的滚轮事件同样生效；
/// 3. **步长口径随设备漂移**：机械滚轮 `scrollingDeltaY` 是 ±1…±3（按行），
///    触控板是几十（按像素），同一行代码在两种设备上量级差 20 倍。
///
/// 用户口径：「我移动贴图的时候，贴图的透明度还会发生变化，越来越透明了」。
/// 这里把「这一格滚轮算不算、算多少」定成一份口径，`PinScrollAdjustmentTests` 直接断言。
public enum PinScrollAdjustment {

    /// 透明度下限：再低贴图就看不清内容了（与设置页默认透明度下限同档）
    public static let minimumAlpha: CGFloat = 0.1
    /// 透明度上限
    public static let maximumAlpha: CGFloat = 1
    /// 缩放下限
    public static let minimumScale: CGFloat = 0.1
    /// 缩放上限
    public static let maximumScale: CGFloat = 10

    /// 滚动阶段（`NSEvent.Phase` 的纯值镜像：本 target 不 import AppKit，由视图层映射一次）
    public enum Phase: Equatable {
        case none, began, changed, ended, cancelled, mayBegin
    }

    /// 一次滚轮事件该做什么
    public enum Intent: Equatable {
        /// 调透明度（⌃ + 滚轮），带本次的透明度增量
        case alpha(CGFloat)
        /// 缩放（裸滚轮），带缩放倍数（乘在 currentScale 上，与改前的乘法语义一致）
        case scale(CGFloat)
        /// 忽略本次事件（惯性 / 拖动会话中 / 零位移 / 阶段结束）
        case ignore
    }

    /// 判定一次滚轮事件
    ///
    /// - Parameters:
    ///   - scrollingDeltaY: 本次事件的纵向滚动量（NSEvent 口径）
    ///   - phase: 滚动阶段
    ///   - momentumPhase: 惯性阶段（触控板松手后仍会连发几十帧）
    ///   - hasPreciseScrollingDeltas: 是否像素级（触控板 / 妙控板为 true，机械滚轮为 false）
    ///   - isControlPressed: 是否按住 ⌃（切透明度）
    ///   - isDragging: 当前是否处于拖动会话
    public static func intent(scrollingDeltaY: CGFloat,
                              phase: Phase,
                              momentumPhase: Phase,
                              hasPreciseScrollingDeltas: Bool,
                              isControlPressed: Bool,
                              isDragging: Bool) -> Intent {
        // 拖动会话中一律不响应：机械滚轮在拖动中会被带出抖动事件，
        // 叠在一起用户看到的就是「一边拖一边变透明」
        guard !isDragging else { return .ignore }
        // 惯性阶段不响应：触控板松手后 momentumPhase 仍为 began/changed 并连发几十帧，
        // 每帧改一次透明度＝松手后继续变
        guard momentumPhase == .none else { return .ignore }
        // 阶段结束 / 取消事件没有有效位移，不该再动数值
        guard phase != .ended, phase != .cancelled else { return .ignore }
        guard scrollingDeltaY != 0 else { return .ignore }
        let step = stepSize(hasPreciseScrollingDeltas: hasPreciseScrollingDeltas)
        return isControlPressed ? .alpha(scrollingDeltaY * step.alphaPerPoint)
                                : .scale(1 + scrollingDeltaY * step.scalePerPoint)
    }

    /// 每 1pt `scrollingDeltaY` 对应的变化量
    ///
    /// 改前一个系数打天下（透明度 0.03）：机械滚轮 5 格就到下限（0.03 × 5 = 0.15），
    /// 触控板轻轻一划（deltaY≈30）直接归零 —— 这就是「越来越透明」的量化来源。
    /// 缩放档保持改前系数（0.02）不变，只把触控板档单列，避免已有手感被改。
    public struct Step: Equatable {
        /// 每 1pt 滚轮量的透明度增量
        public let alphaPerPoint: CGFloat
        /// 每 1pt 滚轮量的缩放比例增量（Multiplication，与改前一致）
        public let scalePerPoint: CGFloat

        public init(alphaPerPoint: CGFloat, scalePerPoint: CGFloat) {
            self.alphaPerPoint = alphaPerPoint
            self.scalePerPoint = scalePerPoint
        }
    }

    /// 按设备取步长：触控板（像素级）用细档，机械滚轮（按行）保持改前档
    public static func stepSize(hasPreciseScrollingDeltas: Bool) -> Step {
        hasPreciseScrollingDeltas
            ? Step(alphaPerPoint: 0.002, scalePerPoint: 0.002)
            : Step(alphaPerPoint: 0.03, scalePerPoint: 0.02)
    }

    /// 透明度钳制（0.1…1）—— 全仓只有这一处定义，视图不再各写一份数字
    public static func clampAlpha(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumAlpha), maximumAlpha)
    }

    /// 缩放钳制（0.1…10）
    public static func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minimumScale), maximumScale)
    }

    /// 新透明度 = 当前 + 增量，再钳制
    public static func alpha(from current: CGFloat, delta: CGFloat) -> CGFloat {
        clampAlpha(current + delta)
    }

    /// 新缩放 = 当前 × 倍数，再钳制（滚轮缩放是乘法语义，与改前一致）
    public static func scale(from current: CGFloat, factor: CGFloat) -> CGFloat {
        clampScale(current * factor)
    }
}
