import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 静默 0 → 显式「不可得」

/// 回归「额度刷新后全是 0」的根因：分母非法 / 字段缺失 / 状态未知时，旧实现直接返回 0，
/// 界面表现为「有窗口 + 0% + 无错误条」，用户无法区分「真是 0」与「取不到」。
///
/// 本套件锁住三条：
/// 1. 换算层：分母非法 / 非有限值一律返回 nil，不再回落 0；
/// 2. 展示层：nil 渲染成「—」且不参与告警分档（0 才是「已用尽」危险档）；
/// 3. provider 映射：limitCredits 缺失的 OpenDesign 窗口判为不可得，而不是 0%。
func runBillingUnavailableValueTests() {
    print("\n🧪 Testing 额度不可得口径...")

    // 1. 换算层：上限为 0 / 负数 / NaN → 不可得（不是 0%）
    assertEqual(BillingPercentMath.remainingFraction(used: 10, limit: 0) == nil, true,
                "上限为 0 判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(used: 10, limit: -5) == nil, true,
                "上限为负判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(used: 10, limit: .nan) == nil, true,
                "上限为 NaN 判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(used: .nan, limit: 100) == nil, true,
                "已用为 NaN 判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(used: 25, limit: 100) ?? -1, 0.75,
                "正常输入照常换算")
    assertEqual(BillingPercentMath.remainingFraction(used: 120, limit: 100) ?? -1, 0,
                "已用超限仍钳制到 0（服务端明确给了数值）")

    assertEqual(BillingPercentMath.remainingFraction(usedPercent: .nan) == nil, true,
                "已用百分比 NaN 判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(usedPercent: .infinity) == nil, true,
                "已用百分比 inf 判为不可得")
    assertEqual(BillingPercentMath.remainingFraction(usedPercent: 100) ?? -1, 0,
                "已用 100% 是明确的 0%")

    // 2. 模型层：nil 不被钳制成 0，NaN 也不当作有效值
    let unavailable = BillingPercentLimit(id: "w", title: "每周", remainingFraction: nil, resetsAt: nil)
    assertEqual(unavailable.isUnavailable, true, "nil 比例判为不可得")
    assertEqual(unavailable.unavailableNote ?? "", "数据不可得", "不可得有说明文案")
    assertEqual(unavailable.remainingFraction == nil, true, "nil 原样保留（不回落 0）")
    let nanLimit = BillingPercentLimit(id: "w", title: "每周", remainingFraction: .nan, resetsAt: nil)
    assertEqual(nanLimit.remainingFraction == nil, true, "NaN 比例判为不可得")
    let zeroLimit = BillingPercentLimit(id: "w", title: "每周", remainingFraction: 0, resetsAt: nil)
    assertEqual(zeroLimit.isUnavailable, false, "明确的 0% 不算不可得")
    assertEqual(zeroLimit.remainingFraction ?? -1, 0, "明确的 0% 原样保留")

    // 内含额度同理：总额度为 0 是分母非法，不是「用完」
    let zeroAllowance = BillingIncludedBalance(remainingUSD: 10, allowanceUSD: 0)
    assertEqual(zeroAllowance.remainingFraction == nil, true, "内含额度分母为 0 判为不可得")

    // 3. 展示层：nil → 「—」，且不吃告警档位
    assertEqual(formatPercent(nil as Double?), billingUnavailablePlaceholder, "精确百分比：不可得显示「—」")
    assertEqual(formatPercentCompact(nil as Double?), billingUnavailablePlaceholder,
                "卡内紧凑百分比：不可得显示「—」")
    assertEqual(formatPercentCompact(0), "0%", "明确的 0% 仍显示 0%")
    assertEqual(BillingCellLayout.level(for: nil), .unavailable, "不可得走独立档位")
    assertEqual(BillingCellLayout.level(for: 0), .danger, "0% 仍是危险档")
    assertEqual(BillingCellLayout.level(for: nil) == .danger, false, "不可得不能被当成 0% 告警")

    // 日志摘要点名「不可得」，否则现场分不清「成功但取不到」与「真 0」
    let summary = formatBalanceSummary(BillingBalance(percentLimits: [
        BillingPercentLimit(id: "a", title: "5 小时", remainingFraction: nil, resetsAt: nil),
        BillingPercentLimit(id: "b", title: "每周", remainingFraction: 0, resetsAt: nil),
    ]))
    assertEqual(summary.contains("不可得"), true, "摘要标出不可得窗口")
    assertEqual(summary.contains("每周 0%"), true, "摘要里真 0% 仍写 0%")

    // 4. provider 映射：limitCredits 缺失 → 该窗口不可得（不是 0%）
    let missingLimit = #"""
    { "eligible": true, "windows": [ { "policyId": "p-missing", "durationSeconds": 18000,
      "usedCredits": "40", "remainingCredits": "0" } ] }
    """#
    let missingBalance = try? OpenDesignBillingProvider.decodeBalance(from: Data(missingLimit.utf8))
    assertEqual(missingBalance?.percentLimits.count ?? -1, 1, "缺 limitCredits 仍产出窗口（不让整份响应失败）")
    assertEqual(missingBalance?.percentLimits.first?.isUnavailable ?? false, true,
                "缺 limitCredits 判为不可得")
    assertEqual(missingBalance?.percentLimits.first?.remainingFraction == nil, true,
                "缺 limitCredits 不产出 0%")

    let missingCredits = #"""
    { "eligible": true, "windows": [ { "policyId": "p-empty", "durationSeconds": 18000 } ] }
    """#
    let emptyBalance = try? OpenDesignBillingProvider.decodeBalance(from: Data(missingCredits.utf8))
    assertEqual(emptyBalance?.percentLimits.first?.isUnavailable ?? false, true,
                "credits 字段全缺判为不可得")

    // 5. 日志三态可分辨：成功 / 不可得 / 空响应各有一条带固定前缀的文案
    let fullBalance = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "a", title: "5 小时", remainingFraction: 0.98, resetsAt: nil),
        BillingPercentLimit(id: "b", title: "每周", remainingFraction: 0.99, resetsAt: nil),
    ])
    let successLine = BillingLogLine.success(providerID: "opencode-go", balance: fullBalance)
    assertEqual(successLine.contains("计费刷新成功（opencode-go）"), true, "成功行带 provider")
    assertEqual(successLine.contains("窗口 2 条"), true, "成功行带窗口数")
    assertEqual(successLine.contains("首个 5 小时=98%"), true, "成功行带首个窗口剩余比例")
    assertEqual(successLine.contains("不可得 0"), true, "成功行标出不可得项数")

    let mixedLine = BillingLogLine.success(
        providerID: "open-design",
        balance: BillingBalance(percentLimits: [
            BillingPercentLimit(id: "a", title: "5 小时", remainingFraction: nil, resetsAt: nil),
        ]))
    assertEqual(mixedLine.contains("不可得 1"), true, "有不可得项时计数如实上报")

    let unavailableLine = BillingLogLine.unavailable(providerID: "open-design", titles: ["5 小时"])
    assertEqual(unavailableLine.contains("额度数据不完整（open-design）"), true, "不可得行带 provider")
    assertEqual(unavailableLine.contains("5 小时"), true, "不可得行点名窗口")
    assertEqual(BillingLogLine.failurePrefix, "计费查询失败", "失败行前缀固定（现场 grep 锚点）")

    // 6. 三态日志样例（现场 log show / 控制台的期望文案，直接取自纯函数）
    print("🧾 成功   " + BillingLogLine.success(providerID: "claude", balance: fullBalance))
    print("🧾 不可得 " + BillingLogLine.unavailable(providerID: "open-design", titles: ["5 小时"]))
    print("🧾 失败   " + BillingLogLine.failurePrefix + "（deepseek）：网络错误")

    // 7. 控制台通道分流探针：info 走 stdout、warning 走 stderr（诊断时 2>/dev/null 只留成功线）
    let probeLogger = ConsoleLogger(minLevel: .info)
    probeLogger.info("额度日志通道探针（info → stdout）")
    probeLogger.warning("额度日志通道探针（warning → stderr）")

    print("✅ 额度不可得口径 works")
}
