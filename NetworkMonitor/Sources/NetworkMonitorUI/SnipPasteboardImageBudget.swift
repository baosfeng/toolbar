import Foundation

// MARK: - 截图复制到剪贴板的体积预算

/// 剪贴板图片的体积预算与档位选择（纯判据，不依赖 AppKit / ImageIO，测试可直接断言）
///
/// 为什么要有预算：2x Retina 全屏截图的无损 PNG 是 1.7MB 量级，用户口径「1MB 已经是上限」。
/// 档位按「先保清晰度、再保无损、最后才有损」排：
/// 1. `png2x`：原像素无损 PNG，小选区走这条（体积天然很小）；
/// 2. `png1x`：降到屏幕点数分辨率再无损编码——Retina 屏按点数显示仍是原生清晰度，
///    像素数只有 1/4（3024×1964 实测 1.73MB → 0.69MB）；
/// 3. `jpeg2x` / `jpeg1x`：复杂画面（满屏照片 / 视频）最后的兜底，文字截图会有轻微振铃。
///
/// 取舍顺序本身就是口径：能无损就不有损、能 2x 就不降采样；预算只决定「先用哪一档」，
/// 不改变选区几何与粘贴时的点数尺寸。
public enum SnipPasteboardImageBudget {

    /// 单张剪贴板图片的体积预算（1 MB）
    public static let byteBudget = 1_048_576

    /// 输出档位（顺序即优先级）
    public enum Tier: Int, CaseIterable, Sendable {
        case png2x
        case png1x
        case jpeg2x
        case jpeg1x

        /// 是否按屏幕点数降采样
        public var isDownscaled: Bool { self == .png1x || self == .jpeg1x }
        /// 是否有损编码
        public var isLossy: Bool { self == .jpeg2x || self == .jpeg1x }
    }

    /// 按候选体积选第一个不超预算的档位
    ///
    /// - Parameter byteCounts: 与 `Tier.allCases` 下标一一对应的编码结果（nil = 该档编码失败）
    /// - Returns: 命中的档位；全部超预算或编码失败返回 nil，由调用方决定兜底策略
    public static func firstFittingTier(byteCounts: [Int?]) -> Tier? {
        for tier in Tier.allCases {
            guard tier.rawValue < byteCounts.count,
                  let bytes = byteCounts[tier.rawValue],
                  bytes > 0, bytes <= byteBudget else { continue }
            return tier
        }
        return nil
    }
}
