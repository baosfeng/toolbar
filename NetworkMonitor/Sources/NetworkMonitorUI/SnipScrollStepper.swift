import CoreGraphics
import Foundation

// MARK: - 滚轮 → 步数的归一化

/// 把滚轮事件换算成"走几步" —— 鼠标滚轮与触控板共用一条通路
///
/// 坑：`NSEvent.scrollingDeltaY` 对鼠标滚轮是"行"（约 ±1～±3），对触控板是"像素"
/// （可 ±0.1 也可 ±40）。直接 `delta > 0 ? 1 : -1` 会让触控板一次滑行触发几十档，
/// 表现为"手指一碰，笔就粗到顶"。而按像素量除以固定系数又会在慢滑时彻底不动。
///
/// 口径：**余量累加** —— 把 delta 累起来，够一个阈值就消费一步、并减掉已消费部分。
/// 鼠标一格 = 1 步；触控板小幅多次滑 = 够阈值才走 1 步；惯性尾不消费。
public struct SnipScrollStepper: Equatable, Sendable {

    /// 消费一步所需的累计量
    ///
    /// - 鼠标滚轮（非精确滚动）：1 —— 一格就是一格，与 Snipaste 的"一格一档"直觉一致
    /// - 触控板（精确滚动）：8 —— 实测触控板一次轻滑约 6～12px，取 8 让"轻滑=1 步、用力滑=2～3 步"
    public static let preciseThreshold: CGFloat = 8
    public static let lineThreshold: CGFloat = 1

    /// 已累计但未消费的余量（跨事件保留）
    private var accumulated: CGFloat = 0

    public init() {}

    /// 喂一个滚轮事件，返回应当推进的步数
    ///
    /// - Parameters:
    ///   - delta: `event.scrollingDeltaY`（已按 `isDirectionInvertedFromDevice` 归一）
    ///   - hasPreciseDeltas: `event.hasPreciseScrollingDeltas`
    ///   - isMomentum: 惯性滑行阶段（`momentumPhase != []`）
    /// - Returns: 正 = 变大，负 = 变小，0 = 这次事件不消费
    public mutating func feed(delta: CGFloat,
                              hasPreciseDeltas: Bool,
                              isMomentum: Bool) -> Int {
        // 惯性尾不消费：用户松手后的滑行不代表还想继续调，
        // 让它继续推进会把"轻轻一滚"滚成一整段（实测能连跳 8 档）。
        guard !isMomentum else {
            accumulated = 0
            return 0
        }
        guard delta.isFinite else { return 0 }
        accumulated += delta
        let threshold = hasPreciseDeltas ? Self.preciseThreshold : Self.lineThreshold
        guard abs(accumulated) >= threshold else { return 0 }
        let steps = (accumulated / threshold).rounded(.towardZero)
        accumulated -= steps * threshold
        // 一次事件最多推进 8 步：极端快速滑动（-120）不该直接跳到端点，
        // 那会让"滚一下"变成"瞬间到顶"，手感反而更差。
        let limit: CGFloat = 8
        let capped = min(max(steps, -limit), limit)
        if capped != steps {
            accumulated = 0
        }
        return Int(capped)
    }

    /// 清空余量（换工具 / 换参数时调，避免上一根旋钮的余量影响下一根）
    public mutating func reset() {
        accumulated = 0
    }
}
