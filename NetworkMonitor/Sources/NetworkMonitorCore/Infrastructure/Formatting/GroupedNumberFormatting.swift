import Foundation

// MARK: - 千分位与定点小数（全项目唯一实现）

/// 数值分组 / 定点小数的唯一实现处 —— Token 页、额度页与日志共用
///
/// 收敛前 `TokenFormat.grouped`、`TokenFormatting.grouped`、`BillingFormat.formatExactNumber`
/// 各起一个 `NumberFormatter`：每次调用都重新装配，locale / 分组符 / 小数位全靠调用点各自记。
/// 千分位是纯字符串操作，倒序走一遍即可，不必每次分配格式化器，结果也就不随 locale 漂移。
public enum GroupedNumberFormatting {

    // MARK: 整数千分位

    /// 整数千分位：76412 → "76,412"、-1234 → "-1,234"
    ///
    /// 用 magnitude 取绝对值：Int.min 直接取负会溢出。
    public static func integer(_ value: Int) -> String {
        let negative = value < 0
        let digits = String(value.magnitude)
        return (negative ? "-" : "") + grouping(digits)
    }

    // MARK: 原值小数

    /// 原值保留最多 `maxFractionDigits` 位小数并加千分位：1234.567 → "1,234.567"
    ///
    /// 「服务端给什么就显示什么」：不补零、不削位；上限 6 位只为消掉浮点运算噪声
    /// （3.74 / 100 * 100 → 3.7399999…，仍应显示 3.74）。
    public static func exact(_ value: Double, maxFractionDigits: Int) -> String {
        guard value.isFinite else { return String(value) }
        var integerPart = String(format: "%.\(max(0, maxFractionDigits))f", value)
        var fractionPart = ""
        if let dot = integerPart.firstIndex(of: ".") {
            fractionPart = String(integerPart[integerPart.index(after: dot)...])
            integerPart = String(integerPart[integerPart.startIndex..<dot])
        }
        while fractionPart.hasSuffix("0") { fractionPart.removeLast() }
        let negative = integerPart.hasPrefix("-")
        if negative { integerPart.removeFirst() }
        let head = (negative ? "-" : "") + grouping(integerPart)
        return fractionPart.isEmpty ? head : head + "." + fractionPart
    }

    // MARK: 定点小数

    /// 定点小数，不带千分位：9.5 → "9.5"、10 → "10.0"
    ///
    /// Token 页把数值与单位分段排版（数值 19pt、单位 9.5pt），这时不能出现逗号。
    public static func decimal(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(max(0, decimals))f", value)
    }

    /// 定点小数并去掉末尾的 0 与小数点：42.00 → "42"、49.058667（2 位）→ "49.06"
    ///
    /// 额度卡大号数字用：服务端会给 1 - 157/50000 这类长小数，
    /// 去尾零后更短，带尾零则会把 19–24pt 的版式撑坏。
    public static func trimmedDecimal(_ value: Double, decimals: Int) -> String {
        var text = decimal(value, decimals: decimals)
        guard text.contains(".") else { return text }
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: 内部

    /// 从末尾倒序每 3 位插一个逗号
    ///
    /// 倒序是因为分组从个位起算；正序要先把长度补齐，倒序则一遍扫完、无中间数组。
    private static func grouping(_ digits: String) -> String {
        var output: [Character] = []
        for (index, digit) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { output.append(",") }
            output.append(digit)
        }
        return String(output.reversed())
    }
}
