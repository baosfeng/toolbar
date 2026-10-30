import Foundation
import NetworkMonitorCore

// MARK: - 系统页色板（定稿值 / 对比度）

/// 色板纯值表断言 — 对比度门槛（图形 ≥3:1 / 文字 ≥4.5:1）× 浅深两套
func runSystemPaletteTests() {
    print("\n🧪 Testing SystemPalette...")
    testPaletteRGBBasics()
    testPaletteTokenCoverage()
    testPaletteContrastPairs()
    testMemoryLadderReversal()
}

// MARK: - RGB 基础

private func testPaletteRGBBasics() {
    let blue = SystemPaletteRGB(hex: 0x0071E3)
    assertEqual(blue.hexString, "#0071E3", "hex 往返")
    assertEqual(blue.contrastRatio(with: blue), 1, "同色对比度 = 1")

    let white = SystemPaletteRGB(hex: 0xFFFFFF)
    let black = SystemPaletteRGB(hex: 0x000000)
    let ratio = white.contrastRatio(with: black)
    assertEqual((ratio - 21).magnitude < 0.01, true, "黑白对比度 ≈ 21:1（WCAG 上限）")
    assertEqual(black.contrastRatio(with: white), ratio, "对比度与前后顺序无关")

    // 边界：越界分量收敛到 0...1，非有限值归 0
    let clamped = SystemPaletteRGB(red: 2, green: -1, blue: .nan)
    assertEqual(clamped.hexString, "#FF0000", "越界 / NaN 分量收敛后仍是合法色")
}

// MARK: - token 覆盖

private func testPaletteTokenCoverage() {
    // 全部 token 在浅 / 深两套下都有值（switch 穷举，这里再守一次「两套都给出」）
    for token in SystemPaletteTokens.Token.allCases {
        let light = SystemPaletteTokens.rgb(token, appearance: .light)
        let dark = SystemPaletteTokens.rgb(token, appearance: .dark)
        assertEqual(light.hexString.count, 7, "\(token.rawValue) 浅色是 6 位 hex")
        assertEqual(dark.hexString.count, 7, "\(token.rawValue) 深色是 6 位 hex")
    }

    // 语义族在深浅两套必须不同（写死双套值，而不是同一色值应付）
    for token in [SystemPaletteTokens.Token.cpu, .gpu, .memoryWired, .loadShort,
                  .disk, .diskInk, .temperature, .battery, .power, .surface] {
        assertEqual(SystemPaletteTokens.hex(token, appearance: .light)
                    != SystemPaletteTokens.hex(token, appearance: .dark),
                    true, "\(token.rawValue) 浅 / 深取值不同")
    }
}

// MARK: - 对比度门槛

private func testPaletteContrastPairs() {
    // 浅 / 深两套逐条断言：文字 ≥ 4.5:1、图形 ≥ 3:1
    for appearance in SystemPaletteTokens.Appearance.allCases {
        for pair in SystemPaletteContrast.pairs {
            let ratio = SystemPaletteContrast.ratio(pair, appearance: appearance)
            let minimum = pair.requirement.minimum
            assertEqual(ratio >= minimum - 0.001, true,
                        "\(appearance.rawValue) \(pair.foreground.rawValue) on \(pair.background.rawValue)"
                        + " = \(String(format: "%.2f", ratio)):1（门槛 \(minimum):1）")
        }
    }
    // 清单本身要覆盖到四个详情页与状态带，不能只测两条样例
    assertEqual(SystemPaletteContrast.pairs.count >= 40, true,
                "对比度清单覆盖 ≥ 40 对（实际 \(SystemPaletteContrast.pairs.count) 对）")
}

// MARK: - 内存三段明度阶梯（深色反向）

private func testMemoryLadderReversal() {
    func luminance(_ token: SystemPaletteTokens.Token,
                   _ appearance: SystemPaletteTokens.Appearance) -> Double {
        SystemPaletteTokens.rgb(token, appearance: appearance).relativeLuminance
    }
    // 浅色：wired 最深、compressed 最浅
    assertEqual(luminance(.memoryWired, .light) < luminance(.memoryActive, .light)
                && luminance(.memoryActive, .light) < luminance(.memoryCompressed, .light),
                true, "浅色三段：wired 最深 → compressed 最浅")
    // 深色反转：深底上「更深」= 更看不见，故 wired 最亮
    assertEqual(luminance(.memoryWired, .dark) > luminance(.memoryActive, .dark)
                && luminance(.memoryActive, .dark) > luminance(.memoryCompressed, .dark),
                true, "深色三段：wired 最亮 → compressed 最暗")
}
