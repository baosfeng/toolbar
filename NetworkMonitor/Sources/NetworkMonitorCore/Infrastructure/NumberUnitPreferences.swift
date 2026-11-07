import Foundation

// MARK: - 数值单位风格

/// 数值单位风格 — 设置页「数值单位」行写入，Core 格式化层读取
///
/// 存储键缺失时一律按 `automatic`：用户升级后没动过该项设置，
/// Token 页与额度页的数字写法必须与改造前完全一致（不默认写任何值）。
public enum NumberUnitStyle: String, CaseIterable, Sendable, Equatable {
    /// 现状口径：K / M / B
    case automatic
    /// 中文口径：万（10^4）/ 亿（10^8）
    case chinese

    /// 设置页展示名
    public var title: String {
        switch self {
        case .automatic: return "自动（K / M / B）"
        case .chinese:   return "中文（万 / 亿）"
        }
    }

    /// 切换后的说明文案（设置页副标题，给出当前档的真实写法示例 + 生效范围）
    ///
    /// 生效范围必须写明：网络页的柱状图标签用固定的短写法（`1.2G` / `34M`），
    /// 那是有意为之——柱子之间的刻度位只有十几 pt，换成「1.6亿」会被裁掉。
    /// 不写清范围时，用户切到中文档会以为设置没生效。
    public var detailText: String {
        switch self {
        case .automatic: return "当前用 K / M / B（默认档：1.6M、225.2K、2.11B）；作用于 Token 与额度页"
        case .chinese:   return "当前用万 / 亿：159,590,000 → 1.6亿、2,650,000 → 265万；作用于 Token 与额度页"
        }
    }
}

// MARK: - 数值单位偏好

/// 数值单位偏好 — 静态键 + 默认值语义 + 不落默认值
///
/// 参考 `BillingProviderPreferences` 的写法：只有用户显式切换才写存储键，
/// 读取时键不存在 / 值非法都退回 `automatic`。测试可注入内存存储，不污染真实偏好。
public struct NumberUnitPreferences {

    /// 存储键（完整键：`display.numberUnitStyle`）
    public static let styleKey = "display.numberUnitStyle"

    private let storage: any KeyValueStorage

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    /// 当前风格（键缺失或值非法 → automatic）
    public var style: NumberUnitStyle {
        guard let raw = storage.string(forKey: Self.styleKey) else { return .automatic }
        return NumberUnitStyle(rawValue: raw) ?? .automatic
    }

    /// 写入风格（仅用户切换时调用，默认值不落盘）
    public func setStyle(_ style: NumberUnitStyle) {
        storage.set(style.rawValue, forKey: Self.styleKey)
    }

    /// 全局生效风格 — 供 Core 格式化层内部读取（不注入存储，跟随设置页写入）
    public static var currentStyle: NumberUnitStyle { NumberUnitPreferences().style }
}

// MARK: - 数值化简

/// 化简结果 — 数值主体与单位后缀分开，业务后缀（tok / 货币符号）由调用方拼接
public struct ScaledNumber: Sendable, Equatable {
    /// 数值主体（含千分位与负号，不含单位）
    public let number: String
    /// 单位后缀（"K" / "M" / "B" / "万" / "亿"；nil = 未到最小单位）
    public let unit: String?

    public init(number: String, unit: String?) {
        self.number = number
        self.unit = unit
    }

    /// 拼成一串（无空格；需要分栏排版时调用方自己用 number / unit 两段）
    public var text: String { number + (unit ?? "") }
}

/// 数值化简纯函数 — Token 页与额度页共用同一口径
///
/// 口径约定（逐条有单测）：
/// - automatic：≥1e9 用 B（2 位小数去尾零）、≥1e6 用 M（≥10 收敛到 1 位、否则 2 位）、
///   ≥1e3 用 K（1 位）、其余整数 + 千分位
/// - chinese：≥1e8 用亿（2 位小数去尾零）、≥1e4 用万（≥100 收敛到 1 位、否则 2 位）、
///   其余整数 + 千分位
/// - **进位不许溢出到下一档的刻度**：缩放后按展示精度四舍五入达到下一档门槛就升档，
///   因此不会出现 `1000.0K` / `1000M` / `10000万`（999,999 → 1M、999,999,999 → 1B、
///   99,999,999 → 1亿）。升档判定的临界值写在 `automatic` / `chinese` 的注释里。
/// - 0 返回 "0"；负数保留负号；NaN / ±inf 降级为「—」且不带单位（不许崩）
/// - 两档在「不足最小单位」的区间都用千分位；automatic 的该区间永远 < 1000，
///   所以千分位只在 chinese 档（1e3…1e4 之间，如 `9,876`）肉眼可见 —— 这是统一的，
///   不是两档各写一套
public enum NumberUnits {

    /// 万 = 10^4
    public static let wanMagnitude: Double = 10_000
    /// 亿 = 10^8
    public static let yiMagnitude: Double = 100_000_000
    /// 非法数值（NaN / ±inf）的降级文案
    public static let invalidText = "—"

    /// 按风格化简
    public static func scale(_ value: Double, style: NumberUnitStyle) -> ScaledNumber {
        guard value.isFinite else { return ScaledNumber(number: invalidText, unit: nil) }
        switch style {
        case .automatic: return automatic(value)
        case .chinese:   return chinese(value)
        }
    }

    /// 当前生效风格下的化简（Core 格式化层默认入口）
    public static func scale(_ value: Double) -> ScaledNumber {
        scale(value, style: NumberUnitPreferences.currentStyle)
    }

    // MARK: - 内部

    /// 现状口径（K / M / B）
    ///
    /// 与改造前 Token 页（`TokenFormatting.abbreviated`）逐条一致：
    /// B 恒 2 位、M 恒 2 位、K 1 位、不足 1000 按四舍五入整数。
    /// （改造前 Core 的 `TokenFormat.abbreviated` 对 ≥10M 收敛到 1 位，与实际在用的
    /// Token 页口径分叉；此处按 Token 页口径统一，M 档更精确：159,590,000 → `159.59M`）
    /// 唯一的新增规则是进位：K 档四舍五入后达 1000 直接按 M 展示（999,999 显示 `1M`
    /// 而不是 `1000.0K`），M 档同理升 B（999,999,999 显示 `1B` 而不是 `1000M`）。
    private static func automatic(_ value: Double) -> ScaledNumber {
        let magnitude = abs(value)
        let millions = value / 1_000_000
        // B 档：≥1e9，或 M 档进位后达 1000（999,999,999 显示 1B 而不是 1000M）
        if magnitude >= 1_000_000_000
            || roundsToAtLeast(1_000, millions, decimals: 2) {
            return ScaledNumber(number: trimmed(value / 1_000_000_000, decimals: 2), unit: "B")
        }
        // M 档：≥1e6，或 K 档进位后达 1000（999,999 显示 1M 而不是 1000.0K）
        if magnitude >= 1_000_000
            || roundsToAtLeast(1_000, value / 1_000, decimals: 1) {
            return ScaledNumber(number: trimmed(millions, decimals: 2), unit: "M")
        }
        if magnitude >= 1_000 {
            return ScaledNumber(number: trimmed(value / 1_000, decimals: 1), unit: "K")
        }
        return ScaledNumber(number: TokenFormat.grouped(Int(value.rounded())), unit: nil)
    }

    /// 中文口径（万 / 亿）
    ///
    /// 万 / 亿 都先取固定小数位再去尾零（与 automatic 同一 trim 规则）：
    /// 159,590,000 → 1.6 亿、2,650,000 → 265 万、7,130,000,000 → 71.3 亿。
    /// 万档在 ≥100（即 ≥100 万）时收敛到 1 位小数：2,650,000 → `265万`、
    /// 159,590,000 → `1.6亿`；亿档恒 2 位（值本身都 ≥1 亿，2 位足够且去尾零后自然收敛）。
    /// 进位规则与 automatic 同源：万档四舍五入后达 1 亿按亿展示
    /// （99,999,999 → `1亿` 而不是 `10000万`）。
    private static func chinese(_ value: Double) -> ScaledNumber {
        let magnitude = abs(value)
        let wans = value / wanMagnitude
        let wansDecimals = abs(wans) >= 100 ? 1 : 2
        // 亿档：≥1e8，或万档进位后达 1 万（99,999,999 显示 1亿 而不是 10000万）
        if magnitude >= yiMagnitude
            || roundsToAtLeast(10_000, wans, decimals: wansDecimals) {
            return ScaledNumber(number: trimmed(value / yiMagnitude, decimals: 2), unit: "亿")
        }
        if magnitude >= wanMagnitude {
            return ScaledNumber(number: trimmed(wans, decimals: wansDecimals), unit: "万")
        }
        return ScaledNumber(number: TokenFormat.grouped(Int(value.rounded())), unit: nil)
    }

    /// 按展示精度四舍五入后是否已达阈值（进位判定；按绝对值计算，负数不影响）
    ///
    /// 例：阈值 1000、缩放值 999.999、精度 1 位 → 1000.0 ≥ 1000 → 结果为真（该升档）。
    private static func roundsToAtLeast(_ threshold: Double, _ scaled: Double,
                                        decimals: Int) -> Bool {
        let factor = pow(10, Double(decimals))
        return (abs(scaled) * factor).rounded() / factor >= threshold
    }

    /// 固定小数位后去掉末尾多余的 0 与孤立小数点（1.60 → 1.6 / 265.00 → 265）
    private static func trimmed(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
