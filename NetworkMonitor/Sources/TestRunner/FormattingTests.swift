import Foundation
import NetworkMonitorCore

// MARK: - Formatting 层：百分比 / 字节 / 千分位 / 相对时间

/// 收敛后的格式化原语断言
///
/// 这些口径原先散在各业务 enum 里（系统页 / Token 页 / 额度页各一份），
/// 这里按「原语」逐条钉住：钳制与 NaN 兜底、整数与小数位、1024 与 1000 两种进位、
/// 千分位，以及相对时间四档的分界点（59/60/3599/3600/86399/86400）。
/// 业务层的既有断言（SystemDetailFormattingTests 等）继续守着「委托后文本不变」。
func runFormattingTests() {
    print("🧪 Testing Formatting 层（百分比 / 字节 / 分组 / 相对时间）...")

    // MARK: 百分比：钳制与非有限值

    assertEqual(PercentFormatting.clampedUnit(0.42), 0.42, "区间内原样返回")
    assertEqual(PercentFormatting.clampedUnit(-0.5), 0, "负值钳到 0")
    assertEqual(PercentFormatting.clampedUnit(1.5), 1, "越界钳到 1")
    assertEqual(PercentFormatting.clampedUnit(.nan), 0, "NaN 归 0")
    assertEqual(PercentFormatting.clampedUnit(.infinity), 0, "+∞ 归 0")
    assertEqual(PercentFormatting.clampedUnit(-.infinity), 0, "-∞ 归 0")

    assertEqual(PercentFormatting.integerNumber(.nan), "0", "NaN 的整数百分比为 0")
    assertEqual(PercentFormatting.integer(.infinity), "0%", "+∞ 的整数百分比为 0%")
    assertEqual(PercentFormatting.compact(.nan), "0%", "NaN 的紧凑百分比为 0%")

    // MARK: 百分比：整数 / 一位小数 / 固定小数位

    assertEqual(PercentFormatting.integerNumber(0.005), "1", "四舍五入到整数、不带 % 号")
    assertEqual(PercentFormatting.integerNumber(0.004), "0", "0.004 → 0")
    assertEqual(PercentFormatting.integer(0.005), "1%", "带 % 号")
    assertEqual(PercentFormatting.integer(1.5), "100%", "越界封顶")
    assertEqual(PercentFormatting.integer(-0.2), "0%", "负比例归 0")

    assertEqual(PercentFormatting.compact(0.012875), "1.3%", "一位小数")
    assertEqual(PercentFormatting.compact(0.40), "40%", "整数不带小数位")
    assertEqual(PercentFormatting.compact(0.644), "64.4%", "非整数保留一位")
    assertEqual(PercentFormatting.compact(0), "0%", "0 → 0%")

    assertEqual(PercentFormatting.fixed(0.095), "9.5%", "默认一位小数")
    assertEqual(PercentFormatting.fixed(0.095, decimals: 2), "9.50%", "两位小数补零")
    assertEqual(PercentFormatting.fixed(1.5), "150.0%", "fixed 不钳制（越界原样暴露）")
    assertEqual(PercentFormatting.fixed(-0.1), "-10.0%", "负比例带符号，不悄悄削成 0")

    // MARK: 百分比：>100% 不削平（进程 CPU 是多核累加）

    assertEqual(PercentFormatting.unclampedFixed(298.4), "298.4%", "298.4% 原样保留")
    assertEqual(PercentFormatting.unclampedFixed(15.77), "15.8%", "一位小数四舍五入")
    assertEqual(PercentFormatting.unclampedFixed(100), "100.0%", "恰好 100%")
    assertEqual(PercentFormatting.unclampedFixed(-3), "0.0%", "负值归 0")
    assertEqual(PercentFormatting.unclampedFixed(2.4, decimals: 0), "2%", "decimals: 0 走整数位")

    // MARK: 字节：1024 进位

    assertEqual(ByteFormatting.binary(0), "0 B", "0 字节")
    assertEqual(ByteFormatting.binary(512), "512 B", "B 级取整")
    assertEqual(ByteFormatting.binary(1_536), "1.5 KB", "KB 级一位小数")
    assertEqual(ByteFormatting.binary(1_048_576), "1.0 MB", "MB 级补一位小数")
    assertEqual(ByteFormatting.binary(16_106_127_360), "15.0 GB", "GB 级")
    assertEqual(ByteFormatting.binary(1_125_899_906_842_624), "1.0 PB", "PB 级封顶")
    assertEqual(ByteFormatting.binary(-5), "0 B", "负容量归 0")
    assertEqual(ByteFormatting.binary(.nan), "0 B", "NaN 归 0 B")
    assertEqual(ByteFormatting.binary(Double(UInt64.max)), "16384.0 PB", "极大值停在 PB 阶")

    assertEqual(ByteFormatting.binaryRate(0), "0 B/s", "0 速率")
    assertEqual(ByteFormatting.binaryRate(1_536), "1.5 KB/s", "KB/s")
    assertEqual(ByteFormatting.binaryRate(-1_536), "1.5 KB/s", "负速率取绝对值")
    assertEqual(ByteFormatting.binaryRate(1_099_511_627_776), "1.0 TB/s", "TB/s")
    assertEqual(ByteFormatting.binaryRate(1_125_899_906_842_624), "1024.0 TB/s",
                "速率上限停在 TB（与改造前文本一致，不冒出 PB/s）")
    assertEqual(ByteFormatting.binaryRate(.infinity), "0 B/s", "+∞ 速率归 0")

    // MARK: 字节：1000 进位

    assertEqual(ByteFormatting.shortDecimal(0), "0B", "0 字节（无空格）")
    assertEqual(ByteFormatting.shortDecimal(500), "500B", "B 级")
    assertEqual(ByteFormatting.shortDecimal(340_000), "340K", "K 级取整")
    assertEqual(ByteFormatting.shortDecimal(1_500), "2K", "K 级四舍五入")
    assertEqual(ByteFormatting.shortDecimal(1_200_000), "1.2M", "M 级一位小数")
    assertEqual(ByteFormatting.shortDecimal(55_000_000), "55.0M", "M 级整数也补一位")
    assertEqual(ByteFormatting.shortDecimal(2_300_000_000), "2.3G", "G 级")
    assertEqual(ByteFormatting.shortDecimal(-2_300_000_000), "2.3G", "负值取绝对值")

    assertEqual(ByteFormatting.fullDecimal(0), "0 KB", "0 字节显示 0 KB（不出现 Zero KB）")
    assertEqual(ByteFormatting.fullDecimal(1_024), "1 KB", "1000 进位：1024 仍是 1 KB")
    assertEqual(ByteFormatting.fullDecimal(1_000_000), "1 MB", "MB 级")
    assertEqual(ByteFormatting.fullDecimal(2_500_000_000), "2.5 GB", "GB 级一位小数")
    assertEqual(ByteFormatting.fullDecimal(12_345), "12 KB", "KB 级取整")

    // MARK: 字节：手写定点的舍入语义与非有限值

    // 这三个原语由手写定点小数接管（复刻 printf 对精确二进制值的正确舍入），
    // 下面钉住三类最容易被手写实现改掉的行为：半偶舍入、非有限值、极端量级回退。
    assertEqual(ByteFormatting.shortDecimal(2_500), "2K", "2.5 半偶舍到 2（printf 是半偶，不是半上）")
    assertEqual(ByteFormatting.shortDecimal(999.5), "1000B", "999.5 半偶进位到 1000，仍留在 B 档")
    assertEqual(ByteFormatting.shortDecimal(-0.0), "0B", "负零取绝对值后是 0")
    assertEqual(ByteFormatting.shortDecimal(.nan), "nanB", "NaN 沿用 printf 文案，不崩")
    assertEqual(ByteFormatting.shortDecimal(.infinity), "infG", "+∞ 落在 G 档并输出 inf")
    assertEqual(ByteFormatting.shortDecimal(1e300), String(format: "%.1fG", 1e300 / 1_000_000_000),
                "极端量级回退到 printf，文本不变")

    assertEqual(ByteFormatting.binary(2.5), "2 B", "2.5 半偶舍到 2")
    assertEqual(ByteFormatting.binary(1.5), "2 B", "1.5 半偶舍到 2")
    assertEqual(ByteFormatting.binary(0.4), "0 B", "小数容量取整到 0")
    assertEqual(ByteFormatting.binary(1_023.9), "1024 B", "B 档取整后可以显示 1024，不抢跑进 KB")
    assertEqual(ByteFormatting.binaryRate(1_536.5), "1.5 KB/s", "速率同样走手写定点")

    // MARK: 千分位与定点小数

    assertEqual(GroupedNumberFormatting.integer(76_412), "76,412", "千分位")
    assertEqual(GroupedNumberFormatting.integer(999), "999", "三位不加分隔")
    assertEqual(GroupedNumberFormatting.integer(1_234_567), "1,234,567", "多位分组")
    assertEqual(GroupedNumberFormatting.integer(0), "0", "0")
    assertEqual(GroupedNumberFormatting.integer(-1_234), "-1,234", "负号在分组外")
    assertEqual(GroupedNumberFormatting.integer(Int.min), "-9,223,372,036,854,775,808", "Int.min 不溢出")

    assertEqual(GroupedNumberFormatting.exact(3.9, maxFractionDigits: 6), "3.9", "原值不补零")
    assertEqual(GroupedNumberFormatting.exact(0.22861, maxFractionDigits: 6), "0.22861", "五位小数原样")
    assertEqual(GroupedNumberFormatting.exact(1_234.567, maxFractionDigits: 6), "1,234.567", "千分位 + 小数")
    assertEqual(GroupedNumberFormatting.exact(76_412, maxFractionDigits: 6), "76,412", "整数不出现小数点")
    assertEqual(GroupedNumberFormatting.exact(3.7399999999999998, maxFractionDigits: 6), "3.74",
                "浮点噪声被 6 位上限消掉")
    assertEqual(GroupedNumberFormatting.exact(0, maxFractionDigits: 6), "0", "0")
    assertEqual(GroupedNumberFormatting.exact(-1_234.5, maxFractionDigits: 6), "-1,234.5", "负值")

    assertEqual(GroupedNumberFormatting.decimal(9.5), "9.5", "一位小数")
    assertEqual(GroupedNumberFormatting.decimal(10), "10.0", "整数补一位小数")
    assertEqual(GroupedNumberFormatting.trimmedDecimal(42, decimals: 2), "42", "去掉 .00")
    assertEqual(GroupedNumberFormatting.trimmedDecimal(49.058667, decimals: 2), "49.06", "四舍五入到两位")
    assertEqual(GroupedNumberFormatting.trimmedDecimal(99.686, decimals: 2), "99.69", "进位后去尾")
    assertEqual(GroupedNumberFormatting.trimmedDecimal(72.5, decimals: 2), "72.5", "只去多余的 0")

    // MARK: 相对时间四档边界

    assertEqual(RelativeTimeFormatting.bucket(seconds: 0), .justNow, "0 秒：刚刚")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 59), .justNow, "59 秒：仍是刚刚")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 60), .minutes(1), "60 秒：1 分钟")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 3_599), .minutes(59), "3599 秒：59 分钟")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 3_600), .hours(1), "3600 秒：1 小时")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 86_399), .hours(23), "86399 秒：23 小时")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 86_400), .days(1), "86400 秒：1 天")
    assertEqual(RelativeTimeFormatting.bucket(seconds: 86_400 * 30), .days(30), "30 天仍按天档")
    assertEqual(RelativeTimeFormatting.bucket(seconds: -1), .justNow, "负值（时钟回拨）按刚刚")
    assertEqual(RelativeTimeFormatting.bucket(seconds: .nan), .justNow, "NaN 按刚刚")
    assertEqual(RelativeTimeFormatting.bucket(seconds: .infinity), .justNow, "+∞ 按刚刚")

    print("✅ Formatting 层 works")
}
