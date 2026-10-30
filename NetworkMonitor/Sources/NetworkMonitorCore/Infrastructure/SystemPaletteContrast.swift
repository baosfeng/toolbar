import Foundation

// MARK: - 色板对比度门槛（图形 ≥3:1 / 文字 ≥4.5:1）

/// 色板对比度约束 — 测试逐条断言，浅 / 深两套各算一遍
///
/// 背景取元素实际所在的底：卡片 token 取对应 wash 卡底，状态带取 bandBackground，
/// 四联小格取 surface。门槛按 WCAG 2.1：图形（曲线 / 面积 / 柱阵 / 堆叠段）≥ 3:1，
/// 文字（数值 / 图例 / 标签）≥ 4.5:1。
public enum SystemPaletteContrast {

    /// 对比度门槛
    public enum Requirement: String, Sendable, CaseIterable {
        /// 图形 / 非文字元素：≥ 3:1
        case graphic
        /// 正文级文字：≥ 4.5:1
        case text

        /// 门槛值
        public var minimum: Double {
            switch self {
            case .graphic: return 3
            case .text: return 4.5
            }
        }
    }

    /// 一对「前景 token on 背景 token」的对比度约束
    public struct Pair: Sendable, Equatable {
        /// 前景 token（曲线 / 色块 / 文字）
        public let foreground: SystemPaletteTokens.Token
        /// 背景 token（元素实际所在的底）
        public let background: SystemPaletteTokens.Token
        /// 门槛
        public let requirement: Requirement

        public init(foreground: SystemPaletteTokens.Token,
                    background: SystemPaletteTokens.Token,
                    requirement: Requirement) {
            self.foreground = foreground
            self.background = background
            self.requirement = requirement
        }
    }

    /// 必须通过对比度的清单
    public static let pairs: [Pair] = {
        var list: [Pair] = []
        func add(_ foreground: SystemPaletteTokens.Token,
                 _ background: SystemPaletteTokens.Token, _ requirement: Requirement) {
            list.append(Pair(foreground: foreground, background: background, requirement: requirement))
        }

        // 常规文字（卡片 / 面板底）
        let surfaces: [SystemPaletteTokens.Token] = [.background, .surface, .cardCPU, .cardGPU,
                                                     .cardMemory, .cardLoad, .cardDisk, .bandBackground]
        for background in surfaces {
            add(.foreground, background, .text)
            add(.foregroundSecondary, background, .text)
            // 详情页脚注（meta）落在各族卡 wash 上：压力卡橙 wash 的余量最小，
            // 必须逐块断言，不能只测面板底与四联小格底
            add(.meta, background, .text)
        }
        add(.muted, .background, .text)
        add(.tabOnInk, .tabOnBackground, .text)

        // 每族 ink 变体（数值 / 图例文字）落在自己的卡底或四联小格底
        add(.cpuInk, .surface, .text)
        add(.cpuInk, .cardCPU, .text)
        add(.gpuInk, .surface, .text)
        add(.gpuInk, .cardGPU, .text)
        add(.memoryInk, .surface, .text)
        add(.memoryInk, .cardMemory, .text)
        add(.loadInk, .surface, .text)
        add(.loadInk, .cardLoad, .text)
        add(.diskInk, .surface, .text)
        add(.diskInk, .cardDisk, .text)
        add(.temperatureInk, .bandBackground, .text)
        add(.batteryInk, .bandBackground, .text)
        add(.wifiInk, .bandBackground, .text)
        add(.powerInk, .bandBackground, .text)
        add(.warnInk, .surface, .text)
        add(.dangerInk, .surface, .text)
        add(.okInk, .bandBackground, .text)

        // 图形级（曲线 / 面积 / 柱阵 / 堆叠段 / 状态带图标）
        add(.cpu, .cardCPU, .graphic)
        add(.cpuSecondary, .cardCPU, .graphic)
        add(.gpu, .cardGPU, .graphic)
        add(.memoryWired, .cardMemory, .graphic)
        add(.memoryActive, .cardMemory, .graphic)
        add(.memoryCompressed, .cardMemory, .graphic)
        add(.loadShort, .cardLoad, .graphic)
        add(.loadMedium, .cardLoad, .graphic)
        add(.loadLong, .cardLoad, .graphic)
        add(.loadReference, .cardLoad, .graphic)
        add(.process, .cardLoad, .graphic)
        add(.disk, .cardDisk, .graphic)
        add(.diskRead, .cardDisk, .graphic)
        add(.diskWrite, .cardDisk, .graphic)
        add(.temperature, .bandBackground, .graphic)
        add(.battery, .bandBackground, .graphic)
        add(.wifi, .bandBackground, .graphic)
        add(.power, .bandBackground, .graphic)
        add(.warn, .surface, .graphic)
        add(.danger, .surface, .graphic)
        add(.ok, .cardMemory, .graphic)
        return list
    }()

    /// 某一对在指定外观下的对比度
    public static func ratio(_ pair: Pair, appearance: SystemPaletteTokens.Appearance) -> Double {
        SystemPaletteTokens.contrastRatio(pair.foreground, on: pair.background,
                                          appearance: appearance)
    }
}
