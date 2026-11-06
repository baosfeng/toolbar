import Foundation

// MARK: - 数值列字号自适应（纯逻辑，可单测）

/// 数值过长时降一档字号 —— 保原值、不截断、不取整
///
/// 背景：额度百分比按服务端原值展示（`49.058667%`），19pt 下这一串能占满半张卡，
/// 另一个窗口的数值就会被挤掉。规则：按「数值段字符数」选字号档，原值一个字符都不丢。
public enum PaneValueSizing {

    /// 数值字号档
    public enum Tier: Equatable {
        /// 19pt（常规）
        case regular
        /// 15pt（长数值：7–9 字符）
        case compact
        /// 13pt（极长数值：≥10 字符）
        case dense
    }

    /// 按数值段字符数选字号档
    ///
    /// 阈值取自实测量测：`296pt` 面板两列时每列约 145pt，
    /// 19pt 等宽数字下 `99.686`（6 字符）约 66pt、`49.058667`（9 字符）约 100pt，
    /// 再长就会与同列的名称/重置时间冲突。
    public static func tier(forNumber number: String) -> Tier {
        switch number.count {
        case ..<7: return .regular
        case 7...9: return .compact
        default: return .dense
        }
    }
}
