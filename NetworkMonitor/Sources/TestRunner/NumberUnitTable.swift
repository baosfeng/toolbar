import Foundation
import NetworkMonitorCore

// MARK: - 单位对照表（人工核验用，不参与默认测试流程）

/// `TestRunner --number-unit-table` 输出「改前 → 改后」实测对照表
///
/// 为什么放在 TestRunner：单元口径在 Core 里，只有这里能脱离 App 直接调用，
/// 输出的数字与用户看到的界面完全同源（都走 `NumberUnits.scale` + tok 后缀拼接）。
/// 每次改动口径后跑一次，把结果贴进交接文档与验收回报。
func runNumberUnitTable() {
    let samples: [(label: String, value: Int)] = [
        ("159,590,000", 159_590_000),
        ("155,850_000", 155_850_000),
        ("2,650,000", 2_650_000),
        ("7,130,000,000", 7_130_000_000),
        ("999,999", 999_999),
        ("999,999,999", 999_999_999),
        ("99,999,999", 99_999_999),
        ("106,000", 106_000),
        ("9,876", 9_876),
        ("0", 0),
    ]

    print("\n| 原始值 | automatic（默认） | chinese（万 / 亿） |")
    print("|---|---|---|")
    for sample in samples {
        let automatic = NumberUnits.scale(Double(sample.value), style: .automatic)
        let chinese = NumberUnits.scale(Double(sample.value), style: .chinese)
        print("| \(sample.label) | \(automatic.number) \(automatic.unit ?? "") tok | "
              + "\(chinese.number) \(chinese.unit ?? "") tok |")
    }

    // 拆分形态（分族卡：数值与单位两段字号不同）
    print("\n拆分形态（Token 分族卡）：")
    for value in [159_590_000, 2_650_000, 398] {
        let split = TokenFormatting.splitTokens(value)
        print("  \(value) → 数值「\(split.number)」单位「\(split.unit)」")
    }
}
