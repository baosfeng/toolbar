import Foundation

// MARK: - 系统页定稿色板（纯值表 · 不依赖 AppKit）

/// sRGB 颜色（分量 0...1）— 色板表与对比度计算共用，UI 层再转成动态 `NSColor`
///
/// 色值写死 sRGB，**不经过 `controlAccentColor` 混色**：v3 曾在 oklab 里把绿色和强调蓝
/// 插值，实测 hue 被拖到 178°（青）。定稿色板每个 token 直接给浅 / 深两套目标值。
public struct SystemPaletteRGB: Sendable, Equatable {

    /// 红分量（0...1）
    public let red: Double
    /// 绿分量（0...1）
    public let green: Double
    /// 蓝分量（0...1）
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
    }

    /// 6 位十六进制（0xRRGGBB）→ sRGB
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 大写 `#RRGGBB` 文本 — 文档与测试断言用
    public var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }

    /// WCAG 2.1 相对亮度（sRGB → 线性化后按 0.2126 / 0.7152 / 0.0722 加权）
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// 两色对比度（WCAG 2.1）：1...21，顺序无关
    public func contrastRatio(with other: SystemPaletteRGB) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let brighter = max(first, second)
        let darker = min(first, second)
        return (brighter + 0.05) / (darker + 0.05)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - 色板 token 表

/// 系统页定稿色板 — 语义 token × 浅 / 深两套写死 sRGB 值
///
/// 单一色值来源：UI 的 `SystemPalette` 只做「token → 动态 NSColor」的转译，
/// 测试直接对本表算对比度（见 `SystemPaletteContrast`），两边不会各写一份色值。
public enum SystemPaletteTokens {

    /// 外观（只区分浅 / 深两档，与 NSAppearance 的 aqua / darkAqua 一一对应）
    public enum Appearance: String, Sendable, CaseIterable {
        case light
        case dark
    }

    /// 语义 token
    public enum Token: String, Sendable, CaseIterable {
        // 底与面
        case background, surface, bandBackground
        case cardCPU, cardGPU, cardMemory, cardLoad, cardDisk
        case track, trackSecondary, grid, tabOnBackground, tabOnInk
        // 文字
        case foreground, foregroundSecondary, muted, meta
        // CPU（蓝）
        case cpu, cpuSecondary, cpuInk
        // GPU（靛）
        case gpu, gpuInk
        // 内存（青绿，三段明度阶梯深浅色反向）
        case memoryWired, memoryActive, memoryCompressed, memoryInk
        // 压力（橙 = 就绪队列；5 / 15 分钟线为次级）
        case loadShort, loadMedium, loadLong, loadReference, loadInk, process
        // 磁盘（石墨 = 容量水位；写 = 琥珀次级）
        case disk, diskRead, diskWrite, diskInk
        // 状态带四族 + 语义色
        case temperature, temperatureInk, battery, batteryInk
        case wifi, wifiInk, power, powerInk
        case warn, warnInk, danger, dangerInk, ok, okInk
    }

    /// 指定外观下的 sRGB 值
    public static func rgb(_ token: Token, appearance: Appearance) -> SystemPaletteRGB {
        SystemPaletteRGB(hex: hex(token, appearance: appearance))
    }

    /// 指定外观下的十六进制值（0xRRGGBB）
    public static func hex(_ token: Token, appearance: Appearance) -> UInt32 {
        switch appearance {
        case .light: return lightHex(token)
        case .dark: return darkHex(token)
        }
    }

    /// 前景 / 背景对比度
    public static func contrastRatio(_ foreground: Token, on background: Token,
                                     appearance: Appearance) -> Double {
        rgb(foreground, appearance: appearance)
            .contrastRatio(with: rgb(background, appearance: appearance))
    }

    // MARK: 浅色

    private static func lightHex(_ token: Token) -> UInt32 {
        switch token {
        case .background: return 0xFFFFFF
        case .surface: return 0xF5F5F7
        case .bandBackground: return 0xF0F0F4
        case .cardCPU: return 0xEAEFF6
        case .cardGPU: return 0xEEEFF6
        case .cardMemory: return 0xEBF1F2
        case .cardLoad: return 0xF3EDEC
        case .cardDisk: return 0xF2EEEC
        case .track: return 0xE4E4EA
        case .trackSecondary: return 0xD6D6DE
        case .grid: return 0xECECF1
        case .tabOnBackground: return 0xD5E4F4
        case .tabOnInk: return 0x0058B3
        case .foreground: return 0x1D1D1F
        case .foregroundSecondary: return 0x3D3D40
        case .muted: return 0x62626A
        case .meta: return 0x6A6A72
        case .cpu: return 0x0071E3
        case .cpuSecondary: return 0x0A4EA8
        case .cpuInk: return 0x0058B3
        case .gpu: return 0x5B5BD6
        case .gpuInk: return 0x4A44B8
        case .memoryWired: return 0x04302D
        case .memoryActive: return 0x0A6B62
        case .memoryCompressed: return 0x0F9A8D
        case .memoryInk: return 0x0B6D64
        case .loadShort: return 0xC2410C
        case .loadMedium: return 0xE0632C
        case .loadLong: return 0x8A2F08
        case .loadReference: return 0x7F7F88
        case .loadInk: return 0xA83A0B
        case .process: return 0xC2410C
        case .disk: return 0x55657A
        case .diskRead: return 0x55657A
        case .diskWrite: return 0xB45309
        case .diskInk: return 0x3F4C5C
        case .temperature: return 0xD9480F
        case .temperatureInk: return 0xA83509
        case .battery: return 0x14913F
        case .batteryInk: return 0x116F33
        case .wifi: return 0x0071E3
        case .wifiInk: return 0x0058B3
        case .power: return 0x8E2FB8
        case .powerInk: return 0x6F2491
        case .warn: return 0xA16207
        case .warnInk: return 0x7C4A06
        case .danger: return 0xB91C1C
        case .dangerInk: return 0x991B1B
        case .ok: return 0x14913F
        case .okInk: return 0x116F33
        }
    }

    // MARK: 深色

    private static func darkHex(_ token: Token) -> UInt32 {
        switch token {
        case .background: return 0x1A1A1C
        case .surface: return 0x242427
        case .bandBackground: return 0x2B2B30
        case .cardCPU: return 0x282D37
        case .cardGPU: return 0x2E2D37
        case .cardMemory: return 0x263033
        case .cardLoad: return 0x332C2C
        case .cardDisk: return 0x322F2B
        case .track: return 0x39393F
        case .trackSecondary: return 0x43434A
        case .grid: return 0x34343A
        case .tabOnBackground: return 0x2A3E57
        case .tabOnInk: return 0x6FB6FF
        case .foreground: return 0xF5F5F7
        case .foregroundSecondary: return 0xD6D6DA
        case .muted: return 0xA8A8AE
        case .meta: return 0x98989D
        case .cpu: return 0x409CFF
        case .cpuSecondary: return 0x2B7FDD
        case .cpuInk: return 0x6FB6FF
        case .gpu: return 0xA89DFF
        case .gpuInk: return 0xBFB6FF
        case .memoryWired: return 0x7CE3D8
        case .memoryActive: return 0x2DD4BF
        case .memoryCompressed: return 0x0F8F83
        case .memoryInk: return 0x5CE3D2
        case .loadShort: return 0xFF8A4C
        case .loadMedium: return 0xC9682F
        case .loadLong: return 0xE8734A
        case .loadReference: return 0x7D7D86
        case .loadInk: return 0xFFAB7D
        case .process: return 0xFF8A4C
        case .disk: return 0xA9B8CC
        case .diskRead: return 0xA9B8CC
        case .diskWrite: return 0xF5B942
        case .diskInk: return 0xC8D4E4
        case .temperature: return 0xFF6B42
        case .temperatureInk: return 0xFFA184
        case .battery: return 0x34D399
        case .batteryInk: return 0x6EE7B7
        case .wifi: return 0x409CFF
        case .wifiInk: return 0x6FB6FF
        case .power: return 0xC48BF5
        case .powerInk: return 0xD9B0FF
        case .warn: return 0xE3B341
        case .warnInk: return 0xF0CF82
        case .danger: return 0xFF6259
        case .dangerInk: return 0xFF9B95
        case .ok: return 0x34D399
        case .okInk: return 0x6EE7B7
        }
    }
}
