import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏「标签换图标」的文本口径

/// 图标化只替换前缀、数值必须留着：去掉前缀后剩下的必须正好是数值部分，
/// 否则菜单栏会出现「图标 + 半个单位」或「图标 + 完整标签」两种错法。
func runMenuBarIconLabelTests() {
    print("🧪 Testing 菜单栏图标化前缀...")

    // 完整标签档：前缀自带尾随空格
    assertEqual(MenuBarIconLabel.valueOnly(text: "Token 7.01亿",
                                           metric: .tokenToday,
                                           style: .full,
                                           customLabels: [:]),
                "7.01亿", "完整标签档去掉 Token 前缀")
    assertEqual(MenuBarIconLabel.valueOnly(text: "CPU 40%",
                                           metric: .cpu,
                                           style: .full,
                                           customLabels: [:]),
                "40%", "完整标签档去掉 CPU 前缀")

    // 短标签档：同一段文本要按短前缀判定
    assertEqual(MenuBarIconLabel.valueOnly(text: "T 7.01亿",
                                           metric: .tokenToday,
                                           style: .short,
                                           customLabels: [:]),
                "7.01亿", "短标签档去掉 T 前缀")

    // 自定义前缀优先于档位
    assertEqual(MenuBarIconLabel.valueOnly(text: "用量 7.01亿",
                                           metric: .tokenToday,
                                           style: .full,
                                           customLabels: ["tokenToday": "用量 "]),
                "7.01亿", "自定义前缀生效")

    // 前缀对不上就不图标化（磁盘 I/O 的「写」片段标签不同）
    assertEqual(MenuBarIconLabel.valueOnly(text: "W 1.2M",
                                           metric: .diskIO,
                                           style: .full,
                                           customLabels: [:]) == nil,
                true, "标签对不上时返回 nil（调用方原样显示）")

    // 数值前补一个空格：防止图标贴着数字
    assertEqual(MenuBarIconLabel.spacedValue("7.01亿"), " 7.01亿", "数值前补空格")
    assertEqual(MenuBarIconLabel.spacedValue(""), "", "空串不补空格")
}
