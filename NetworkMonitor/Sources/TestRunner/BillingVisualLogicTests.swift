import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 额度页 / Token 页视觉口径（纯函数断言）
//
// 文件名带 BillingVisual 前缀：TestRunner 目录由两位 agent 共用，避免与行为侧测试文件重名。

// MARK: - 额度页 Hero 派生

func runBillingHeroLogicTests() {
    print("\n🧪 Testing BillingHeroLogic...")
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // 1. 取剩余最小者（不是第一个、也不是最大）
        let inputs: [BillingHeroInput] = [
            BillingHeroInput(providerName: "Ollama", windowTitle: "会话", remaining: 0.95, resetsAt: now),
            BillingHeroInput(providerName: "Ollama", windowTitle: "每周", remaining: 0.42, resetsAt: now),
            BillingHeroInput(providerName: "Open Design", windowTitle: "每周", remaining: 0.49, resetsAt: now),
        ]
        let hero = BillingHeroLogic.lowestRemaining(inputs)
        assertEqual(hero?.providerName, "Ollama", "取剩余最小者所属 provider")
        assertEqual(hero?.windowTitle, "每周", "取剩余最小者的窗口")
        assertEqual(hero?.remaining, 0.42, "剩余比例原样带回")
        assertEqual(hero?.label, "最低剩余 · Ollama 每周", "Hero 标签拼法")

        // 2. 同值取输入顺序靠前的那一个（输入顺序 = 注册顺序）
        let tie: [BillingHeroInput] = [
            BillingHeroInput(providerName: "A", windowTitle: "每周", remaining: 0.4, resetsAt: nil),
            BillingHeroInput(providerName: "B", windowTitle: "每周", remaining: 0.4, resetsAt: nil),
        ]
        assertEqual(BillingHeroLogic.lowestRemaining(tie)?.providerName, "A", "同值按注册顺序取第一个")

        // 3. 全部无数据 → nil（Hero 显示「—」而不是 0%）
        let noData: [BillingHeroInput] = [
            BillingHeroInput(providerName: "A", windowTitle: "每周", remaining: nil, resetsAt: nil),
            BillingHeroInput(providerName: "B", windowTitle: "每月", remaining: nil, resetsAt: nil),
        ]
        assertEqual(BillingHeroLogic.lowestRemaining(noData), nil, "全无数据返回 nil")
        assertEqual(BillingHeroLogic.lowestRemaining([]), nil, "空输入返回 nil")

        // 4. 无数据的窗口不参与比较（不会被当成 0%）
        let mixed: [BillingHeroInput] = [
            BillingHeroInput(providerName: "A", windowTitle: "每周", remaining: nil, resetsAt: nil),
            BillingHeroInput(providerName: "B", windowTitle: "每月", remaining: 0.2, resetsAt: nil),
        ]
        assertEqual(BillingHeroLogic.lowestRemaining(mixed)?.providerName, "B", "nil 不参与比较")

        // 5. 越界值钳制：>1 按 1、<0 按 0（0 是最紧急，不能丢）
        let outOfRange: [BillingHeroInput] = [
            BillingHeroInput(providerName: "A", windowTitle: "每周", remaining: 1.8, resetsAt: nil),
            BillingHeroInput(providerName: "B", windowTitle: "每月", remaining: -0.3, resetsAt: nil),
        ]
        let clamped = BillingHeroLogic.lowestRemaining(outOfRange)
        assertEqual(clamped?.providerName, "B", "负值钳到 0 后最紧急")
        assertEqual(clamped?.remaining, 0.0, "越界负值钳制为 0")

        // 6. 单窗口
        let single = [BillingHeroInput(providerName: "Solo", windowTitle: "会话",
                                       remaining: 0.5, resetsAt: nil)]
        assertEqual(BillingHeroLogic.lowestRemaining(single)?.remaining, 0.5, "单窗口直接返回")
}

// MARK: - 数值 / 单位分列

func runPaneValueFormattingTests() {
    print("\n🧪 Testing PaneValueFormatting...")
        // 英文档
        assertEqual(PaneValueFormatting.split("159.59 M tok"),
                    PaneValueFormatting.Split(number: "159.59", unit: "M tok"), "英文档：数值 + M tok")
        assertEqual(PaneValueFormatting.split("1,239 次"),
                    PaneValueFormatting.Split(number: "1,239", unit: "次"), "千分位 + 中文单位")
        assertEqual(PaneValueFormatting.split("95%"),
                    PaneValueFormatting.Split(number: "95", unit: "%"), "百分号当单位")
        assertEqual(PaneValueFormatting.split("3.74%"),
                    PaneValueFormatting.Split(number: "3.74", unit: "%"), "两位小数百分比")

        // 中文档（设置切到万 / 亿）
        assertEqual(PaneValueFormatting.split("1.60 亿 tok"),
                    PaneValueFormatting.Split(number: "1.60", unit: "亿 tok"), "中文档：亿 + tok")
        assertEqual(PaneValueFormatting.split("10.6万"),
                    PaneValueFormatting.Split(number: "10.6", unit: "万"), "中文档：万不带空格")
        assertEqual(PaneValueFormatting.split("42.04%"),
                    PaneValueFormatting.Split(number: "42.04", unit: "%"), "额度页四位百分比")

        // 边界
        assertEqual(PaneValueFormatting.split("2675"),
                    PaneValueFormatting.Split(number: "2675", unit: ""), "纯数字无单位")
        assertEqual(PaneValueFormatting.split(""),
                    PaneValueFormatting.Split(number: "", unit: ""), "空串")
        assertEqual(PaneValueFormatting.split("   "),
                    PaneValueFormatting.Split(number: "", unit: ""), "全空白")
        assertEqual(PaneValueFormatting.split("—"),
                    PaneValueFormatting.Split(number: "—", unit: ""), "占位符原样")
        assertEqual(PaneValueFormatting.split("$0.01718"),
                    PaneValueFormatting.Split(number: "$0.01718", unit: ""), "金额不拆货币符号")
        assertEqual(PaneValueFormatting.split("M tok"),
                    PaneValueFormatting.Split(number: "M tok", unit: ""), "纯单位不拆（数值为空时整串留 number）")
}

// MARK: - 卡片排布判据

func runPaneCardLayoutTests() {
    print("\n🧪 Testing PaneCardLayout...")
        assertEqual(PaneCardLayout.limitColumns(windowCount: 0), 0, "0 窗口 → 0 列")
        assertEqual(PaneCardLayout.limitColumns(windowCount: 1), 1, "1 窗口 → 1 列")
        assertEqual(PaneCardLayout.limitColumns(windowCount: 2), 2, "2 窗口 → 2 列")
        assertEqual(PaneCardLayout.limitColumns(windowCount: 3), 3, "3 窗口 → 3 列")
        assertEqual(PaneCardLayout.limitColumns(windowCount: 5), 3, "超过 3 个窗口钳到 3 列")

        assertEqual(PaneCardLayout.isCompactCell(columnCount: 1), false, "1 列非窄格")
        assertEqual(PaneCardLayout.isCompactCell(columnCount: 2), false, "2 列非窄格")
        assertEqual(PaneCardLayout.isCompactCell(columnCount: 3), true, "3 列窄格（角标分行）")

        // 320pt 面板 296pt 可用：长主体名放不下时返回 false
        assertEqual(PaneCardLayout.headerFits(nameWidth: 80, segmentWidth: 120), true, "短名 + 分段放得下")
        assertEqual(PaneCardLayout.headerFits(nameWidth: 160, segmentWidth: 120), false, "长名 + 分段放不下")
}

// MARK: - 数值列字号自适应

func runPaneValueSizingTests() {
    print("\n🧪 Testing PaneValueSizing...")
    assertEqual(PaneValueSizing.tier(forNumber: "42"), .regular, "两位整数常规档")
    assertEqual(PaneValueSizing.tier(forNumber: "99.686"), .regular, "6 字符常规档")
    assertEqual(PaneValueSizing.tier(forNumber: "49.0587"), .compact, "7 字符降一档")
    assertEqual(PaneValueSizing.tier(forNumber: "49.058667"), .compact, "9 字符仍降一档")
    assertEqual(PaneValueSizing.tier(forNumber: "100.1234567"), .dense, "11 字符最紧档")
    assertEqual(PaneValueSizing.tier(forNumber: "—"), .regular, "占位符常规档")
}

// MARK: - 空态文案

func runBillingEmptyStateLogicTests() {
    print("\n🧪 Testing BillingEmptyStateLogic...")
    let registered = BillingEmptyStateLogic.copy(for: .noProviderRegistered)
    assertEqual(registered.title, "还没有额度 Provider", "注册表为空：标题")
    assertEqual(registered.action, "打开设置", "注册表为空：按钮文案")

    let unconfigured = BillingEmptyStateLogic.copy(for: .allUnconfigured)
    assertEqual(unconfigured.title, "还没有可查询的额度 Provider", "全部未配置：标题")
    assertEqual(unconfigured.action, "去设置配置", "全部未配置：按钮文案")

    let disabled = BillingEmptyStateLogic.copy(for: .allDisabled)
    assertEqual(disabled.title, "额度 Provider 已全部停用", "全部停用：标题")
    assertEqual(disabled.action, "去设置启用", "全部停用：按钮文案")

    let unknown = BillingEmptyStateLogic.copy(for: .unknown)
    assertEqual(unknown.title, "还没有可查询的额度 Provider", "未知原因：标题与未配置同档")
    assertEqual(unknown.action, "去设置配置", "未知原因：按钮文案")

    // 三档标题互不相同（避免「换了原因看不出差别」）
    let titles = [registered.title, unconfigured.title, disabled.title]
    assertEqual(Set(titles).count, 3, "三档标题互不相同")
}

// MARK: - 额度卡大号百分比（紧凑档）

/// 额度卡大号数字与 Token 页同一条排版线：最多 2 位小数、去尾零、非法值降级。
///
/// 服务端会返回 `1 - 157/50000` 这类长小数（实测 99.686% / 49.058667%），
/// 19–24pt 下原值会把半张卡撑满；这一组断言锁住「卡内收紧凑、读屏仍保留原值」两条线。
func runBillingPercentDisplayTests() {
    print("\n🧪 Testing 额度卡百分比排版...")

    // 分列后的数值段：大号数字实际渲染的就是这一段
    func number(_ fraction: Double) -> String {
        PaneValueFormatting.split(formatPercentCompact(fraction)).number
    }
    assertEqual(number(0.42000), "42", "42.00% 去尾零 → 42")
    assertEqual(number(0.49058667), "49.06", "六位小数收到 2 位")
    assertEqual(number(0.99686), "99.69", "99.686 四舍五入到 2 位")
    assertEqual(number(0.95), "95", "整数百分比不补零")
    assertEqual(number(1), "100", "满额")
    assertEqual(PaneValueFormatting.split(formatPercentCompact(0.49058667)).unit, "%",
                "单位段仍是 %（分列排版依赖它）")
    assertEqual(number(.nan), "—", "NaN 降级为占位符，不出 nan%")

    // 与精确档的关系：读屏与日志口径不变，长度明显更短
    assertEqual(formatPercent(0.49058667), "49.058667%", "读屏口径仍为原值")
    assertEqual(number(0.49058667).count < formatPercent(0.49058667).count, true,
                "大号数字段比原值短（否则版式仍会被撑坏）")

    // 长数值不会因此掉到最紧一档
    assertEqual(PaneValueSizing.tier(forNumber: number(0.99686)), .regular,
                "紧凑后 99.69 回到常规 19pt 档")
}
