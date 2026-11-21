import Foundation

// MARK: - 平滑曲线

/// 滚动平滑曲线 —— 五次 smoothstep（6p⁵ − 15p⁴ + 10p³）
///
/// 与 Mos 同族但独立实现：只保留「进度 0…1 → 位移比例 0…1」这一条数学性质
/// （两端一阶 / 二阶导都为 0，起止不顿挫；关于 0.5 对称），不搬运任何外部源码。
///
/// 纯函数、无 AppKit：Core 层只做数值，TestRunner 能直接断言端点、对称性与单调性。
public enum SmoothScrollCurve {

    /// 曲线名（设置页说明与日志用；不含实现细节，改名即代表换算法）
    public static let displayName = "smoothstep（五次）"

    /// 进度 → 位移比例
    ///
    /// - Parameter progress: 0…1 的归一化进度；越界按端点收敛，NaN 按 0 处理
    /// - Returns: 0…1 的位移比例（value(0) == 0、value(1) == 1、单调不减）
    public static func value(at progress: Double) -> Double {
        guard progress.isFinite else { return progress > 0 ? 1 : 0 }
        let p = min(max(progress, 0), 1)
        return p * p * p * (p * (p * 6 - 15) + 10)
    }

    /// 把一次滚动拆成 `count` 帧时，每帧分到的位移权重
    ///
    /// 权重由曲线差分给出（第 i 帧 = value(i/n) − value((i−1)/n)），
    /// 因此 **Σ 权重恒为 1**，逐帧回投的位移总量与原始增量一致，不会越滚越远 / 越滚越少。
    /// `count <= 1` 时只有一帧（整段位移一次走完）。
    public static func weights(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [1] }
        var weights: [Double] = []
        weights.reserveCapacity(count)
        var previous = 0.0
        for index in 1...count {
            let current = value(at: Double(index) / Double(count))
            weights.append(current - previous)
            previous = current
        }
        return weights
    }
}
