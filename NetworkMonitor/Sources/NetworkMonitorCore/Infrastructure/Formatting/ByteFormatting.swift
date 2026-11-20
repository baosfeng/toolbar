import Foundation

// MARK: - 字节口径（全项目唯一实现）

/// 容量与速率的唯一实现处 —— 菜单栏、系统页、传输日志共用
///
/// 两套进位并存是刻意的，不能合并：
/// - 1024 进位（`binary` / `binaryRate`）：系统监控的容量与读写速率，与「活动监视器」一致；
/// - 1000 进位（`shortDecimal` / `fullDecimal`）：网速与文件体积，与 Finder / 运营商口径一致。
///
/// 收敛前 `SystemMetricsFormatting.byteRateText`、`SystemDetailFormatting.byteCountText`、
/// `SystemProcessBoard.formatBytes`、`Core.formatSpeedShort` / `formatBytesFull` 各写一份，
/// 单位阶与小数位互相抄错的风险始终存在。
public enum ByteFormatting {

    /// 1024 进位的单位阶：B 取整、K 及以上 1 位小数
    private static let binaryUnits = ["B", "KB", "MB", "GB", "TB", "PB"]

    /// 速率上限只到 TB/s —— 改造前的速率口径不列 PB，保留它让既有返回文本一字不变
    private static let binaryRateMaxUnitIndex = 4

    // MARK: 1024 进位

    /// 容量，1024 进位：512 → "512 B"、1_048_576 → "1.0 MB"、0 → "0 B"
    ///
    /// 负值与非法值归 0：容量没有负值，出现即采样异常，显示 0 B 比 "-5 B" 更像占位。
    public static func binary(_ bytes: Double) -> String {
        guard bytes.isFinite else { return "0 B" }
        return scaledBinary(max(0, bytes), maxUnitIndex: binaryUnits.count - 1)
    }

    /// 速率，1024 进位并在尾部加 "/s"：1_536 → "1.5 KB/s"、-1_536 → "1.5 KB/s"
    ///
    /// 取绝对值：差分采样窗口错位会算出负值，负速率没有展示意义。
    public static func binaryRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "0 B/s" }
        return scaledBinary(abs(bytesPerSecond), maxUnitIndex: binaryRateMaxUnitIndex) + "/s"
    }

    // MARK: 1000 进位

    /// 容量短写，1000 进位、单位紧跟数字：1_200_000_000 → "1.2G"、340_000 → "340K"、500 → "500B"
    ///
    /// 菜单栏宽度是硬约束，所以不留空格；K 级取整、M/G 级一位小数是既有的可读性折中
    /// （分档与改造前 `formatSpeedShort` 完全一致，含 999.9M 这类"跨档回退"的观感）。
    public static func shortDecimal(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1_000_000_000...: return String(format: "%.1fG", magnitude / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", magnitude / 1_000_000)
        case 1_000...: return String(format: "%.0fK", magnitude / 1_000)
        default: return String(format: "%.0fB", magnitude)
        }
    }

    /// 容量完整写法，1000 进位、数值与单位之间带空格："1.2 MB"；0 → "0 KB"
    ///
    /// 0 单独出 "0 KB"：系统格式化器对 0 会返回本地化的「Zero KB」，菜单里看着像异常值。
    /// 自适应精度（KB 取整 / MB 一位 / GB 两位）与单位文案（1000 以下本地化的 "bytes"）
    /// 由系统格式化器决定，手写会改变既有文本，因此这里只把 0 值与配置收敛到一处。
    public static func fullDecimal(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.includesCount = true
        formatter.allowedUnits = [.useAll]
        formatter.isAdaptive = true
        // clamping：超过 Int64.max 的极端入参在改造前会直接崩，这里退化成上限值而不是崩溃
        return formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    // MARK: 内部

    /// 1024 进位逐级折算；单位阶到顶后不再进位（超大值保持最大单位下的数值）
    private static func scaledBinary(_ value: Double, maxUnitIndex: Int) -> String {
        let cap = min(max(0, maxUnitIndex), binaryUnits.count - 1)
        var scaled = value
        var index = 0
        while scaled >= 1024, index < cap {
            scaled /= 1024
            index += 1
        }
        let unit = binaryUnits[index]
        guard index > 0 else { return String(format: "%.0f %@", scaled, unit) }
        return String(format: "%.1f %@", scaled, unit)
    }
}
