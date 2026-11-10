import CoreGraphics

// MARK: - 画笔粗细档位（纯逻辑，可单测）

/// 画笔粗细的档位与步进
///
/// Snipaste 把「滚轮 / 1 2 / [ ]」列为默认调整画笔粗细的三条通路，
/// 本项目此前只能点开二级面板换线宽。档位表与步进收在这里，
/// 工具条面板、方括号与数字键、滚轮共用同一份口径，不会出现「面板里有 8、按键跳到 6」。
public enum SnipLineWidthStepper {

    /// 可选线宽档位（与二级面板显示的一档一档对齐）
    public static let widths: [CGFloat] = [2, 4, 8]

    /// 按档位步进：delta 为正加粗、为负变细，越界时停在端点
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
}
