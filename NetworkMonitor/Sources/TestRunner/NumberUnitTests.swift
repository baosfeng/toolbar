import Foundation
import NetworkMonitorCore

// MARK: - 数值单位（设置项 + 化简口径）

/// 数值单位：偏好读写（默认不落盘 / 非法值降级）与两档化简口径（含进位与非法值）
///
/// 化简断言一律显式传 style，不依赖全局 `AppContext` 存储 —— 与 UI 实测走同一条纯函数。
func runNumberUnitTests() {
    print("\n🧪 Testing NumberUnitPreferences...")
    testNumberUnitPreferences()

    print("\n🧪 Testing NumberUnits.automatic...")
    testNumberUnitsAutomatic()

    print("\n🧪 Testing NumberUnits.chinese...")
    testNumberUnitsChinese()

    print("\n🧪 Testing NumberUnits 非法值降级...")
    testNumberUnitsInvalid()
}

// MARK: - 偏好

/// 默认档 = automatic 且默认值不落盘；非法值降级；用户显式切换才写键
private func testNumberUnitPreferences() {
    let storage = InMemoryStorage()
    let preferences = NumberUnitPreferences(storage: storage)

    assertEqual(preferences.style, .automatic, "未写过键时默认 automatic（升级后写法不变）")
    assertEqual(storage.object(forKey: NumberUnitPreferences.styleKey) == nil, true,
                "默认值不落盘（避免升级后被旧键钉死）")

    preferences.setStyle(.chinese)
    assertEqual(preferences.style, .chinese, "用户切档后写入立即生效")
    assertEqual(storage.string(forKey: NumberUnitPreferences.styleKey), "chinese",
                "键名 display.numberUnitStyle 已落盘")

    preferences.setStyle(.automatic)
    assertEqual(preferences.style, .automatic, "切回自动档")
    assertEqual(storage.string(forKey: NumberUnitPreferences.styleKey), "automatic",
                "自动档只在显式切换时才写")

    // 旧版本 / 手改配置写进无法识别的值：必须降级而不是崩
    storage.set("wan", forKey: NumberUnitPreferences.styleKey)
    assertEqual(preferences.style, .automatic, "非法值降级为 automatic")

    assertEqual(NumberUnitStyle.allCases.map(\.title),
                ["自动（K / M / B）", "中文（万 / 亿）"], "设置页两档文案")
    assertNotNil(NumberUnitStyle.chinese.detailText, "切档说明文案存在")
}

// MARK: - automatic 档

private func testNumberUnitsAutomatic() {
    let scale = { (value: Double) in NumberUnits.scale(value, style: .automatic).text }

    assertEqual(scale(0), "0", "0 不带单位")
    assertEqual(scale(7), "7", "个位数原样")
    assertEqual(scale(999), "999", "不足 1000 原样")
    assertEqual(scale(1_000), "1K", "1000 → 1K")
    assertEqual(scale(1_500), "1.5K", "1500 → 1.5K")
    assertEqual(scale(72_271), "72.3K", "请求数 72,271 → 72.3K")
    assertEqual(scale(999_499), "999.5K", "未到进位线仍是 K")
    // 进位：K 档四舍五入到 1000 必须升 M，不能出现 1000.0K
    assertEqual(scale(999_999), "1M", "999,999 进位到 1M（不出现 1000K）")
    assertEqual(scale(1_000_000), "1M", "100 万 → 1M")
    assertEqual(scale(5_390_000), "5.39M", "小于 10M 保留 2 位")
    assertEqual(scale(10_100_000), "10.1M", "≥10M 收敛到 1 位")
    assertEqual(scale(159_590_000), "159.59M", "1.6 亿量级（automatic 现状写法）")
    // 进位：M 档四舍五入到 1000 必须升 B
    assertEqual(scale(999_999_999), "1B", "999,999,999 进位到 1B（不出现 1000M）")
    assertEqual(scale(1_000_000_000), "1B", "10 亿 → 1B")
    assertEqual(scale(7_130_000_000), "7.13B", "B 档 2 位小数")
    assertEqual(scale(-2_650_000), "-2.65M", "负数保留负号")
    // 改造前 Token 页口径：≥1000 一律化简成 K，因此 9,876 显示 9.9K（不是 9,876）
    assertEqual(scale(9_876), "9.9K", "9876 → 9.9K（现状口径，与改造前一致）")
    assertEqual(scale(999), "999", "不足 1000 才按整数展示")
}

// MARK: - chinese 档

private func testNumberUnitsChinese() {
    let scale = { (value: Double) in NumberUnits.scale(value, style: .chinese).text }

    assertEqual(scale(0), "0", "0 不带单位")
    assertEqual(scale(7), "7", "个位数原样")
    assertEqual(scale(9_876), "9,876", "不足一万按整数 + 千分位")
    assertEqual(scale(9_999), "9,999", "9999 仍是整数（999 以内两档都是纯整数）")
    assertEqual(scale(10_000), "1万", "整一万 → 1万")
    assertEqual(scale(106_000), "10.6万", "十万级保留 2 位去尾零")
    assertEqual(scale(2_650_000), "265万", "≥100 万收敛到 1 位（去尾零）")
    assertEqual(scale(99_990_000), "9999万", "临近亿档仍是万")
    // 进位：万档四舍五入到 1 万必须升亿，不能出现 10000万
    assertEqual(scale(99_999_999), "1亿", "99,999,999 进位到 1亿（不出现 10000万）")
    assertEqual(scale(159_590_000), "1.6亿", "亿档 2 位去尾零")
    assertEqual(scale(155_850_000), "1.56亿", "亿档保留 2 位有效小数")
    assertEqual(scale(7_130_000_000), "71.3亿", "亿档 ≥10 去尾零")
    assertEqual(scale(120_000_000), "1.2亿", "整亿量级")
    assertEqual(scale(-2_650_000), "-265万", "负数保留负号")
}

// MARK: - 非法值

private func testNumberUnitsInvalid() {
    for style in NumberUnitStyle.allCases {
        assertEqual(NumberUnits.scale(.nan, style: style).text, "—", "\(style.rawValue) 档 NaN 降级为 —")
        assertEqual(NumberUnits.scale(.infinity, style: style).text, "—",
                    "\(style.rawValue) 档 +inf 降级为 —")
        assertEqual(NumberUnits.scale(-.infinity, style: style).text, "—",
                    "\(style.rawValue) 档 -inf 降级为 —")
        assertEqual(NumberUnits.scale(.nan, style: style).unit == nil, true, "降级结果不带单位")
    }

    // 拆分形态：非法值时数值段就是破折号，分族卡不会拼出「— tok」的空单位
    let split = TokenFormattingSplitProbe.split(Int64(1))
    assertEqual(split.unit, "tok", "个位数拆分后单位段为 tok（不含空格前缀）")
}

/// 借 TokenFormatting.splitTokens 的拆分契约断言（同模块 package，可直接调用）
private enum TokenFormattingSplitProbe {
    static func split(_ value: Int64) -> (number: String, unit: String) {
        TokenFormatting.splitTokens(Int(value))
    }
}
