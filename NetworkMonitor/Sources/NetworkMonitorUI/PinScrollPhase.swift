import Foundation

// MARK: - 贴图窗滚动阶段映射

/// `NSEvent.Phase` / `NSEvent.MomentumPhase` → `PinScrollAdjustment.Phase`
///
/// 拆出来单独一个文件，是为了让 `PinScrollAdjustment` 保持「不 import AppKit」：
/// 可断言的判据在 UI 库，取值映射留在允许 import AppKit 的调用侧。
/// 但本 target（NetworkMonitorUI）也不 import AppKit —— 所以映射写成「整数页码」形式，
/// 由 App 侧在取事件时直接传 NSEvent.Phase.rawValue。见 PinWindow.scrollWheel。
extension PinScrollAdjustment.Phase {

    /// 按事件阶段的原始位值映射（NSEvent.Phase 的 rawValue 是位掩码，同一时刻可能多段并存）
    ///
    /// 兜底口径：**只要带 .ended / .cancelled 位就落终态**（这两个位出现时本次手势已经结束，
    /// 该帧没有有效位移）；其余情况按「是否带 .none 之外的位」判 began / changed。
    public init(rawPhaseBits bits: UInt) {
        guard bits != 0 else {
            self = .none
            return
        }
        if bits & PinScrollPhaseBits.cancelled != 0 {
            self = .cancelled
        } else if bits & PinScrollPhaseBits.ended != 0 {
            self = .ended
        } else if bits & PinScrollPhaseBits.mayBegin != 0 {
            self = .mayBegin
        } else if bits & PinScrollPhaseBits.began != 0 {
            self = .began
        } else {
            self = .changed
        }
    }
}

/// `NSEvent.Phase` / `NSEvent.MomentumPhase` 的位值常量（AppKit 定义，此处只取需要的位）
///
/// 直接写字面量与 AppKit 的 `NSEvent.Phase` 取值一致（began = 1, changed = 2, ended = 4,
/// cancelled = 8, mayBegin = 32）。放在这里而不 import AppKit：UI 库要保持无 AppKit 依赖。
public enum PinScrollPhaseBits {
    public static let began: UInt = 1
    public static let changed: UInt = 2
    public static let ended: UInt = 4
    public static let cancelled: UInt = 8
    public static let mayBegin: UInt = 32
}
