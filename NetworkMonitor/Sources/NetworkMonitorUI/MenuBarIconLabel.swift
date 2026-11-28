import Foundation
import NetworkMonitorCore

// MARK: - 菜单栏「标签换成图标」的文本口径

/// 某一项指标改成图标显示时，状态栏上还剩什么文本
///
/// 状态栏片段是「前缀 + 数值」（Token 7.01亿）。图标化只替换**前缀**，
/// 数值必须留着 —— 否则菜单栏只剩一枚图标，用户看不出是多少。
/// 判定用「文本是否以该档位的前缀开头」，自定义前缀同样生效，因此不需要第二份标签表。
public enum MenuBarIconLabel {

    /// 去掉前缀后的剩余文本（数值 + 可能的单位）
    /// - Returns: nil 表示这段文本不以前缀开头（例如磁盘 I/O 的「写」片段标签不同），调用方应原样显示文本
    public static func valueOnly(text: String,
                                 metric: MenuBarMetric,
                                 style: MenuBarLabelStyle,
                                 customLabels: [String: String]) -> String? {
        let prefix = MenuBarLabelResolver.primaryLabel(for: metric,
                                                       style: style,
                                                       customLabels: customLabels)
        guard !prefix.isEmpty, text.hasPrefix(prefix) else { return nil }
        return String(text.dropFirst(prefix.count))
    }

    /// 图标化时给数值补一个前导空格（7.01亿 → 空格 + 7.01亿），避免图标贴着数字
    ///
    /// 前缀本身常带尾随空格（Token 后面那个空格），把这段一起丢掉后数值会紧贴图标；
    /// 这里补回一个空格，保持「图标 + 空格 + 数值」的节奏与文本档一致。
    public static func spacedValue(_ value: String) -> String {
        value.isEmpty ? value : " " + value
    }
}
