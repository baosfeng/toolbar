import Foundation
import NetworkMonitorUI

// MARK: - 菜单栏显示口径（布局 / 单位 / 刷新周期 / 分页重算）

// MARK: - 刷新周期与定时器重建判据

func runMenuBarDisplayTests() {
    print("\n🧪 Testing MenuBarDisplayLogic...")

    // 夹取：沿用 1...10 秒；非有限值 / 非正数回落下界
    // 下界 0.5 秒：极致档要用 0.5 秒周期，非法输入仍回落到下界
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(0), 0.5, "0 秒回落到下界 0.5 秒")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(-3), 0.5, "负数回落到下界 0.5 秒")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(.nan), 0.5, "NaN 回落到下界 0.5 秒")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(.infinity), 0.5, "无穷大视为非法输入，回落到下界 0.5 秒")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(0.5), 0.5, "极致档 0.5 秒不得被夹回 1 秒")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(2), 2, "设置页 2 秒档原样生效")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(5), 5, "设置页 5 秒档原样生效")
    assertEqual(MenuBarDisplayLogic.clampedRefreshInterval(60), 10, "超出上界夹到 10 秒")
    assertEqual(MenuBarDisplayLogic.refreshIntervalOptions, [1, 2, 5], "设置页只给 1/2/5 三档")

    // 定时器重建判据：只有夹取后的周期真的不同才重建
    assertEqual(MenuBarDisplayLogic.needsTimerRebuild(currentInterval: 1, desiredInterval: 2), true, "1 秒 → 2 秒需要重建")
    assertEqual(MenuBarDisplayLogic.needsTimerRebuild(currentInterval: 2, desiredInterval: 2), false, "周期相同不重建")
    assertEqual(MenuBarDisplayLogic.needsTimerRebuild(currentInterval: 10, desiredInterval: 60), false, "夹取后等价（10 秒）不重建")
    assertEqual(MenuBarDisplayLogic.needsTimerRebuild(currentInterval: 2, desiredInterval: 2.000001), true, "夹取不取整，微小差异仍会重建")
    assertEqual(MenuBarDisplayLogic.needsTimerRebuild(currentInterval: 0, desiredInterval: 15), true, "越界值按夹取结果比较")

    // MARK: 单位写法

    // short 沿用现有紧凑写法，custom 回落 short
    assertEqual(MenuBarDisplayLogic.speedText(shortText: "1.2M", unitStyle: .short), "1.2M", "short 保持紧凑")
    assertEqual(MenuBarDisplayLogic.speedText(shortText: "1.2M", unitStyle: .custom), "1.2M", "custom 回落 short")
    assertEqual(MenuBarDisplayLogic.speedText(shortText: "1.2M", unitStyle: .full), "1.2 MB/s", "full 带空格全称")
    assertEqual(MenuBarDisplayLogic.fullSpeedText("0B"), "0 B/s", "0 字节全称")
    assertEqual(MenuBarDisplayLogic.fullSpeedText("340K"), "340 KB/s", "K 级全称")
    assertEqual(MenuBarDisplayLogic.fullSpeedText("1.2G"), "1.2 GB/s", "G 级全称")
    assertEqual(MenuBarDisplayLogic.fullSpeedText("2.3T"), "2.3 TB/s", "T 级全称")
    assertEqual(MenuBarDisplayLogic.fullSpeedText("abc"), "abc B/s", "认不出单位时补默认单位")

    // MARK: 布局

    assertEqual(MenuBarDisplayLogic.layout(fromRawValue: "twoLine"), .twoLine, "偏好 rawValue 对接两行")
    assertEqual(MenuBarDisplayLogic.layout(fromRawValue: "未知值"), .singleLine, "非法 rawValue 回落单行")
    assertEqual(MenuBarDisplayLogic.unitStyle(fromRawValue: "full"), .full, "偏好 rawValue 对接全称")
    assertEqual(MenuBarDisplayLogic.unitStyle(fromRawValue: "未知值"), .short, "非法 rawValue 回落紧凑")

    assertEqual(MenuBarDisplayLogic.usesTwoLines(.singleLine), false, "单行不换行")
    assertEqual(MenuBarDisplayLogic.usesTwoLines(.twoLine), true, "两行换行")
    assertEqual(MenuBarDisplayLogic.usesTwoLines(.card), true, "card 按两行呈现（同一实现）")

    // 文本拼接：单行保持原样；两行按指标均分上下行、奇数时上行多一段
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["↓1.2M", "↑340K"], layout: .singleLine, separator: "  "),
                "↓1.2M  ↑340K", "单行按密度分隔符拼接")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["↓1.2M", "↑340K", "CPU 40%"], layout: .singleLine, separator: "  "),
                "↓1.2M  ↑340K  CPU 40%", "单行不换行")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["↓1.2M", "↑340K"], layout: .twoLine, separator: "  "),
                "↓1.2M\n↑340K", "两行上下各一段")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["↓1.2M", "↑340K", "CPU 40%"], layout: .twoLine, separator: "  "),
                "↓1.2M  ↑340K\nCPU 40%", "奇数三段时上行多一段")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["↓1.2M"], layout: .twoLine, separator: "  "),
                "↓1.2M", "只有一段时不产生空行")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: [], layout: .twoLine, separator: "  "), "", "无片段返回空串")
    assertEqual(MenuBarDisplayLogic.statusTitle(parts: ["A", "B", "C"], layout: .card, separator: "  "),
                "A  B\nC", "card 与 twoLine 同一拼法")

    // MARK: 分页可见性重算

    // 枚举原始值：网络 0 / 剪贴板 1 / 传送 2 / 额度 3 / Token 4 / 系统 5
    assertEqual(MenuBarDisplayLogic.resolvedTab(current: 0, visibleTabs: [0, 1, 2, 3, 4, 5]), 0, "当前页仍可见时保持不变")
    assertEqual(MenuBarDisplayLogic.resolvedTab(current: 5, visibleTabs: [0, 1, 2, 3, 4]), 0, "隐藏当前页（系统页）后落到第一个可见页")
    assertEqual(MenuBarDisplayLogic.resolvedTab(current: 4, visibleTabs: [1, 2, 3, 4]), 4, "只隐藏别的页时当前页不动")
    assertEqual(MenuBarDisplayLogic.resolvedTab(current: 0, visibleTabs: [3, 4]), 3, "落到第一个可见页而不是固定首页")
    assertEqual(MenuBarDisplayLogic.resolvedTab(current: 2, visibleTabs: []), 2, "无可见页时保持原值，由调用方兜底")

    print("✅ MenuBarDisplayLogic 菜单栏显示口径 works")
}
