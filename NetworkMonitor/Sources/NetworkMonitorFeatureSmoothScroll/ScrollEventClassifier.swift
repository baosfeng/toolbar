import Foundation

// MARK: - 滚轮事件识别

/// 滚轮事件识别 —— 纯函数，无 AppKit / 无 CoreGraphics 状态
///
/// 只回答两个问题：
/// 1. 这个事件是不是我们自己回投的（靠 `eventSourceUserData` 魔数）——是则必须原样放行，
///    否则回投事件会再被 tap 捕获、再拆一次，形成自我放大的死循环；
/// 2. 这个事件是不是「纯鼠标滚轮」——只有它才做平滑；触控板与惯性滚动一律放行。
///
/// 判据刻意保守：只要带 phase（触控板 / 妙控鼠标 / 驱动级平滑）或带 momentumPhase
/// （惯性滑行）或标记为连续滚动，就当作「不是普通滚轮」，绝不接管。漏平滑只是少一点手感，
/// 误平滑则是在用户没要求的地方改写输入。
public enum ScrollEventClassifier {

    /// 回投事件的魔数标记（ASCII "SCROLL"，写进 `eventSourceUserData`）
    ///
    /// 选 `eventSourceUserData` 而不是自定义 field：该字段对系统不透明、不参与投递语义，
    /// 且只在本机进程回投的事件上出现，不会与真实 HID 事件撞值。
    public static let injectionMarker: Int64 = 0x5343_524F_4C4C

    /// 是否本引擎回投的事件
    public static func isOwnInjectedEvent(sourceUserData: Int64,
                                          marker: Int64 = injectionMarker) -> Bool {
        sourceUserData == marker
    }

    /// 是否可平滑的纯鼠标滚轮
    ///
    /// - Parameters:
    ///   - phase: `scrollWheelEventScrollPhase`（触控板 / 妙控鼠标非 0）
    ///   - momentumPhase: `scrollWheelEventMomentumPhase`（惯性滚动非 0）
    ///   - isContinuous: `scrollWheelEventIsContinuous`（像素级连续滚动）
    public static func isSmoothableMouseWheel(phase: Int64,
                                              momentumPhase: Int64,
                                              isContinuous: Bool) -> Bool {
        phase == 0 && momentumPhase == 0 && !isContinuous
    }
}
