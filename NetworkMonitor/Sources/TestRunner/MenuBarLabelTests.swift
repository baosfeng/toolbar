import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 菜单栏标签 / 单位口径

/// 覆盖三处口径：
/// 1. 17 项的完整 / 短标签逐字（`MenuBarMetric`）
/// 2. 标签解析的三档优先级与空格规则（`MenuBarLabelResolver`）
/// 3. 计数类数值写法（`MenuBarDisplayLogic.countText`）：跟随「数值单位」、full 档不带 /s
func runMenuBarLabelTests() {
    print("\n🧪 Testing MenuBarLabel style...")

    // MARK: 完整标签 = 接入偏好之前的逐字前缀（任何一条改动都会改老用户外观）

    assertEqual(MenuBarMetric.downSpeed.fullLabel, "↓", "下载速度前缀与数值相连")
    assertEqual(MenuBarMetric.upSpeed.fullLabel, "↑", "上传速度前缀与数值相连")
    assertEqual(MenuBarMetric.todayTraffic.fullLabel, "Today ", "今日流量原前缀带尾随空格")
    assertEqual(MenuBarMetric.weekTraffic.fullLabel, "Wk ", "本周流量原前缀")
    assertEqual(MenuBarMetric.cpu.fullLabel, "CPU ", "CPU 原前缀")
    assertEqual(MenuBarMetric.gpu.fullLabel, "GPU ", "GPU 原前缀")
    assertEqual(MenuBarMetric.memory.fullLabel, "MEM ", "内存原前缀")
    assertEqual(MenuBarMetric.memoryPressure.fullLabel, "P ", "内存压力原前缀")
    assertEqual(MenuBarMetric.diskFree.fullLabel, "Disk ", "磁盘空闲原前缀")
    assertEqual(MenuBarMetric.diskIO.fullLabel, "R ", "磁盘 I/O 读片段前缀")
    assertEqual(MenuBarMetric.diskIO.secondaryFullLabel, "W ", "磁盘 I/O 写片段前缀")
    assertEqual(MenuBarMetric.wifi.fullLabel, "WiFi ", "Wi-Fi 原前缀")
    assertEqual(MenuBarMetric.battery.fullLabel, "BAT ", "电量原前缀")
    assertEqual(MenuBarMetric.thermal.fullLabel, "Temp ", "温度原前缀")
    assertEqual(MenuBarMetric.load.fullLabel, "L ", "负载原前缀")
    assertEqual(MenuBarMetric.tokenToday.fullLabel, "Token ", "Token 今日原前缀")
    assertEqual(MenuBarMetric.tokenCacheHit.fullLabel, "HIT ", "缓存命中率原前缀")
    assertEqual(MenuBarMetric.tokenWeek.fullLabel, "7d ", "Token 7 天原前缀")
    assertEqual(MenuBarMetric.cpu.secondaryFullLabel, nil, "只有磁盘 I/O 有第二片段")

    // MARK: 短标签：1–2 字符，17 项全覆盖、无空串

    for metric in MenuBarMetric.allCases {
        let short = metric.shortLabel
        assertEqual(!short.trimmingCharacters(in: .whitespaces).isEmpty, true, "\(metric.rawValue) 短标签不得为空")
        assertEqual(short.count <= 2, true, "\(metric.rawValue) 短标签不超过 2 字符（含尾随空格）")
        assertEqual(metric.fullLabel.count >= short.count, true, "\(metric.rawValue) 短标签不应比完整标签更长")
    }
    assertEqual(MenuBarMetric.tokenToday.shortLabel, "T ", "Token 今日短标签")
    assertEqual(MenuBarMetric.cpu.shortLabel, "C ", "CPU 短标签")
    assertEqual(MenuBarMetric.thermal.shortLabel, "° ", "温度用度数符号")

    // MARK: 三档优先级：逐项自定义 > 档位 > 内置默认

    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .full, customLabels: [:]),
                "CPU ", "无自定义时取完整标签")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .short, customLabels: [:]),
                "C ", "无自定义时取短标签")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .short, customLabels: ["cpu": "核 "]),
                "核 ", "自定义优先于档位")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .full, customLabels: ["cpu": "  X  "]),
                "X ", "自定义值去首尾空白后补一个尾随空格")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .full, customLabels: ["cpu": ""]),
                "CPU ", "自定义为空串等于没填")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .full, customLabels: ["cpu": "   "]),
                "CPU ", "自定义为纯空白等于没填")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .cpu, style: .full, customLabels: ["cpu": "X "]),
                "X ", "已带尾随空格的自定义值不重复补空格")

    // ↓ / ↑ 是符号不是文字：历史上直接与数值相连（↓1.2M），自定义时也不补空格
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .downSpeed, style: .full, customLabels: [:]),
                "↓", "下载速度默认前缀不带空格")
    assertEqual(MenuBarLabelResolver.primaryLabel(for: .downSpeed, style: .short, customLabels: ["downSpeed": "v"]),
                "v", "下载速度自定义也不补尾随空格")

    // 磁盘 I/O 的写片段单独存键，不与读共用
    assertEqual(MenuBarLabelResolver.secondaryLabel(for: .diskIO, style: .full, customLabels: [:]),
                "W ", "写片段默认标签")
    assertEqual(MenuBarLabelResolver.secondaryLabel(for: .diskIO, style: .full,
                                                    customLabels: [MenuBarLabelResolver.diskWriteKey: "写 "]),
                "写 ", "写片段自定义走独立键")
    assertEqual(MenuBarLabelResolver.secondaryLabel(for: .cpu, style: .full, customLabels: [:]),
                nil, "非磁盘 I/O 没有第二片段")

    // 占位提示写默认值（弹窗里那行灰字）
    assertEqual(MenuBarLabelResolver.placeholder(for: .tokenToday, style: .full),
                "默认 Token / 短标签 T", "占位提示给两项默认写法")
    assertEqual(MenuBarLabelResolver.placeholder(for: .upSpeed, style: .short),
                "默认 ↑ / 短标签 ↑", "符号类两项默认一致")

    // MARK: 计数类数值写法（跟随「数值单位」，full 档不带 /s）

    // automatic：K / M / B
    assertEqual(MenuBarDisplayLogic.countText(2_510_000_000, numberStyle: .automatic, unitStyle: .short),
                "2.51B", "automatic 紧凑档用 B")
    assertEqual(MenuBarDisplayLogic.countText(2_510_000_000, numberStyle: .automatic, unitStyle: .full),
                "2.51 B", "automatic full 档只补空格、不带 /s")
    assertEqual(MenuBarDisplayLogic.countText(225_200, numberStyle: .automatic, unitStyle: .short),
                "225.2K", "K 档")
    assertEqual(MenuBarDisplayLogic.countText(500, numberStyle: .automatic, unitStyle: .full),
                "500", "不足最小单位时没有单位可补")
    assertEqual(MenuBarDisplayLogic.countText(0, numberStyle: .automatic, unitStyle: .full),
                "0", "0 不产生单位")

    // chinese：万 / 亿，且中文单位不插空格
    assertEqual(MenuBarDisplayLogic.countText(159_590_000, numberStyle: .chinese, unitStyle: .short),
                "1.6亿", "中文档走亿")
    assertEqual(MenuBarDisplayLogic.countText(159_590_000, numberStyle: .chinese, unitStyle: .full),
                "1.6亿", "中文单位 full 档不插空格")
    assertEqual(MenuBarDisplayLogic.countText(2_650_000, numberStyle: .chinese, unitStyle: .full),
                "265万", "中文档走万")

    // 异常值降级（NaN / inf）不许崩
    assertEqual(MenuBarDisplayLogic.countText(.nan, numberStyle: .automatic, unitStyle: .full),
                NumberUnits.invalidText, "NaN 降级为「—」")
    assertEqual(MenuBarDisplayLogic.countText(.infinity, numberStyle: .chinese, unitStyle: .full),
                NumberUnits.invalidText, "无穷大降级为「—」")

    // MARK: 端到端：17 项片段（走真实上下文，标签 + 单位一起看）

    let totals = HarnessUsageTotals(today: HarnessTokenUsage(uncachedInput: 2_500_000_000),
                                    thisWeek: HarnessTokenUsage(uncachedInput: 159_590_000),
                                    allTime: .zero,
                                    cacheHitRate: 0.7312)
    let context = MenuBarStatusContext(downSpeed: 1_234_567,
                                       upSpeed: 340_000,
                                       snapshot: nil,
                                       todayTraffic: 2_510_000_000,
                                       weekTraffic: 225_200,
                                       tokenTotals: totals,
                                       unitStyle: .short,
                                       numberUnitStyle: .automatic,
                                       labelStyle: .full,
                                       customLabels: [:])

    assertEqual(MenuBarStatusParts.parts(for: .downSpeed, context: context), ["↓1.2M"], "下载速度与原写法逐字一致")
    assertEqual(MenuBarStatusParts.parts(for: .upSpeed, context: context), ["↑340K"], "上传速度与原写法逐字一致")
    assertEqual(MenuBarStatusParts.parts(for: .todayTraffic, context: context), ["Today 2.51B"],
                "今日流量按计数写法，不再带 /s")
    assertEqual(MenuBarStatusParts.parts(for: .tokenToday, context: context), ["Token 2.5B"],
                "Token 今日按计数写法")
    assertEqual(MenuBarStatusParts.parts(for: .tokenWeek, context: context), ["7d 159.59M"],
                "Token 7 天按计数写法")
    assertEqual(MenuBarStatusParts.parts(for: .tokenCacheHit, context: context), ["HIT 73%"], "命中率四舍五入")

    // 切到中文档：同一条上下文只换「数值单位」，计数类立刻变、速率类不动
    let chinese = MenuBarStatusContext(downSpeed: 1_234_567, upSpeed: 340_000, snapshot: nil,
                                       todayTraffic: 2_510_000_000, weekTraffic: 225_200,
                                       tokenTotals: totals, unitStyle: .short,
                                       numberUnitStyle: .chinese, labelStyle: .full,
                                       customLabels: [:])
    assertEqual(MenuBarStatusParts.parts(for: .tokenToday, context: chinese), ["Token 25亿"], "切中文档后 Token 走亿")
    assertEqual(MenuBarStatusParts.parts(for: .downSpeed, context: chinese), ["↓1.2M"], "速率类不受数值单位影响")

    // 短标签档：前缀变短，数值口径不变
    let shortLabels = MenuBarStatusContext(downSpeed: 1_234_567, upSpeed: 340_000, snapshot: nil,
                                           todayTraffic: 2_510_000_000, weekTraffic: 225_200,
                                           tokenTotals: totals, unitStyle: .short,
                                           numberUnitStyle: .automatic, labelStyle: .short,
                                           customLabels: [:])
    assertEqual(MenuBarStatusParts.parts(for: .tokenToday, context: shortLabels), ["T 2.5B"], "短标签档：Token → T")
    assertEqual(MenuBarStatusParts.parts(for: .downSpeed, context: shortLabels), ["↓1.2M"], "箭头符号不受档位影响")

    // 取不到值时返回空数组（不给「—」占位）
    assertEqual(MenuBarStatusParts.parts(for: .cpu, context: context), [], "无快照时 CPU 不出片段")
    assertEqual(MenuBarStatusParts.parts(for: .diskIO, context: context), [], "无快照时磁盘 I/O 不出片段")

    // 组装：只有已启用的项按顺序出；全部关闭时回落下载速度
    let made = MenuBarStatusParts.make(enabled: [.downSpeed, .tokenToday],
                                       order: MenuBarMetric.defaultOrder,
                                       context: context)
    assertEqual(made, ["↓1.2M", "Token 2.5B"], "按偏好顺序只组装已启用项")
    assertEqual(MenuBarStatusParts.make(enabled: [], order: MenuBarMetric.defaultOrder, context: context),
                ["1.2M"], "全部关闭时回落下载速度（无前缀，与原实现一致），状态栏不空白")

    print("✅ MenuBarLabel 菜单栏标签 / 单位口径 works")
}
