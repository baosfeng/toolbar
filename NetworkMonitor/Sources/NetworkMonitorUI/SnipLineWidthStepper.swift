import CoreGraphics
import NetworkMonitorCore

// MARK: - 画笔粗细（纯逻辑，可单测）

/// 画笔粗细的档位、步进与自定义范围
///
/// Snipaste 把「滚轮 / 1 2 / [ ]」列为默认调整画笔粗细的三条通路，
/// 且线宽是**连续值**（1–40），不是三档。本项目此前把线宽锁死在 [2,4,8] 三档，
/// 用户想要 3pt 或 16pt 无处可去。现在：
/// - 档位表 `widths` 只作为「二级面板的快捷项」，不再是全部可选值；
/// - 快捷键 / 滚轮走 `step`，按 1pt 连续微调、越过档位不吸附；
/// - 任意值走 `clamp`（设置页与数值输入共用同一份上下限）。
public enum SnipLineWidthStepper {

    /// 二级面板的快捷档位（一档一档对齐显示）
    public static let widths: [CGFloat] = [2, 4, 8]

    /// 线宽可选范围：与解析器 / 渲染器同一口径（唯一真源在 Core 的 SnipLineWidthRange）
    public static var range: ClosedRange<CGFloat> { SnipLineWidthRange.range }

    /// 连续步进的粒度（1pt：既够细，又不会滑过整个范围）
    public static let stepGranule: CGFloat = 1

    /// 把任意线宽夹进合法范围（NaN / 无穷回落默认值）
    public static func clamp(_ width: CGFloat) -> CGFloat {
        SnipLineWidthRange.clamp(width)
    }

    /// 按档位步进：delta 为正加粗、为负变细，越界时停在端点
    ///
    /// 保留档位吸附语义（二级面板与 `[` / `]` 的历史口径一致）。
    ///
    /// - Parameters:
    ///   - width: 当前线宽（可能不是档位值，例如设置页给的默认线宽）
    ///   - delta: 步进次数（1 / -1）
    public static func step(from width: CGFloat, by delta: Int) -> CGFloat {
        guard delta != 0, !widths.isEmpty else { return width }
        // 平局取更细的一档（1 与 4 等距 3 时落到 2 而不是 4）：
        // 严格小于比较让 min 保留第一个最小值，档位表本身按从小到大排列
        let nearest = widths.indices.min {
            abs(widths[$0] - width) < abs(widths[$1] - width)
        } ?? 0
        let target = min(max(nearest + (delta > 0 ? 1 : -1), 0), widths.count - 1)
        return widths[target]
    }

    /// 连续步进：在任意线宽上按粒度加减，不吸附到档位
    ///
    /// 这是「滚轮调粗细」与「1 / 2 快捷键」现在走的口径：
    /// 用户可以把笔停在 3pt、5pt、13pt 这些档位之外的值上。
    public static func continuousStep(from width: CGFloat, by delta: Int) -> CGFloat {
        guard delta != 0 else { return clamp(width) }
        return clamp(width + CGFloat(delta) * stepGranule)
    }
}
