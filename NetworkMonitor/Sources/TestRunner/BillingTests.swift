import Foundation
import NetworkMonitorCore

// MARK: - 计费 provider 测试

/// 计费模块测试：格式化与模型计算（解码 / 注册表 / 凭据用例见 BillingDecodingTests.swift）
///
/// 覆盖正常 / 边界 / 异常三类场景；网络层错误映射由 HTTP 状态码分支保证，
/// 这里只验证纯函数与解码逻辑，不依赖外网。
func runBillingTests() {
    print("\n🧪 Testing BillingFormat...")
    testBillingFormat()

    print("\n🧪 Testing BillingModels...")
    testBillingModels()

    print("\n🧪 Testing BillingRefreshScheduler...")
    testBillingRefreshScheduler()

    print("\n🧪 Testing BillingLimitLayout...")
    testBillingLimitLayout()

    print("\n🧪 Testing BillingDecoding...")
    runBillingDecodingTests()

    print("✅ Billing 计费模块 works")
}

// MARK: - 格式化

private func testBillingFormat() {
    assertEqual(formatUSD(72.5), "$72.5", "不补尾零")
    assertEqual(formatUSD(0.01718), "$0.01718", "小额原值展示")
    assertEqual(formatUSD(0.22861), "$0.22861", "原值 5 位小数不四舍五入")
    assertEqual(formatUSD(0), "$0", "零值")
    assertEqual(formatUSD(1_234.567), "$1,234.567", "千分位 + 不四舍五入")

    assertEqual(formatCreditAmount(76_412), "76,412", "credits 千分位")
    assertEqual(formatCreditAmount(3.9), "3.9", "credits 小数原值")

    assertEqual(formatTokenCount(0), "0", "0 token")
    assertEqual(formatTokenCount(9_999), "9999", "不足一万原样")
    assertEqual(formatTokenCount(10_000), "1.0万", "整一万")
    assertEqual(formatTokenCount(106_000), "10.6万", "十万级")
    assertEqual(formatTokenCount(120_000_000), "1.2亿", "亿级")

    assertEqual(formatPercent(0.725), "72.5%", "比例不取整")
    // 回归：服务端返回 3.9% 时曾被取整成「4%」，额度页必须原样展示
    assertEqual(formatPercent(0.039), "3.9%", "3.9% 原样展示")
    assertEqual(formatPercent(0.0374), "3.74%", "3.74% 原样展示（消除浮点噪声）")
    assertEqual(formatPercent(1.0 / 3), "33.333333%", "循环小数按原值展示")
    assertEqual(formatPercent(0), "0%", "0%")
    assertEqual(formatPercent(1), "100%", "100%")
    assertEqual(formatPercent(1.4), "100%", "超界钳制")
}

// MARK: - 模型计算

private func testBillingModels() {
    let period = BillingPeriod(start: Date(timeIntervalSince1970: 0),
                               end: Date(timeIntervalSince1970: 20 * 86_400))
    assertEqual(period.remainingDays(at: Date(timeIntervalSince1970: 0)), 20, "周期剩余天数")
    assertEqual(period.remainingDays(at: Date(timeIntervalSince1970: 21 * 86_400)), 0, "已结束返回 0")
    assertEqual(formatPercent(period.progress(at: Date(timeIntervalSince1970: 10 * 86_400))), "50%",
                "周期进度 50%")

    let included = BillingIncludedBalance(remainingUSD: 72.5, allowanceUSD: 100, period: period)
    assertEqual(included.remainingFraction, 0.725, "剩余比例")
    let zeroAllowance = BillingIncludedBalance(remainingUSD: 10, allowanceUSD: 0)
    assertEqual(zeroAllowance.remainingFraction, 0, "总额度为 0 时比例为 0")

    let balance = BillingBalance(included: included, purchasedUSD: 25,
                                 percentLimits: [BillingPercentLimit(id: "session", title: "会话",
                                                                     remainingFraction: 0.75, resetsAt: nil)])
    assertEqual(balance.totalAvailableUSD ?? -1, 97.5, "可用总额 = 内含剩余 + 已购")
    assertEqual(balance.isEmpty, false, "有额度数据不为空")

    let purchasedOnly = BillingBalance(purchasedUSD: 25)
    assertEqual(purchasedOnly.totalAvailableUSD ?? -1, 25, "仅已购额度")

    let empty = BillingBalance()
    assertEqual(empty.totalAvailableUSD == nil, true, "无额度时可用总额为 nil")
    assertEqual(empty.isEmpty, true, "空余额")

    let clampedLimit = BillingPercentLimit(id: "weekly", title: "每周", remainingFraction: 1.8, resetsAt: nil)
    assertEqual(clampedLimit.remainingFraction, 1, "比例上限钳制")
    assertEqual(clampedLimit.badge == nil, true, "未设置角标时为空")

    let rateLimited = BillingPercentLimit(id: "window:rolling", title: "5 小时",
                                          remainingFraction: 0, resetsAt: nil, badge: "已限流")
    assertEqual(rateLimited.badge, "已限流", "角标原样保留")

    // 日志摘要：三窗口按顺序拼接，已限流窗口带角标
    let monthlyLimited = BillingPercentLimit(id: "window:monthly", title: "每月",
                                             remainingFraction: 0, resetsAt: nil, badge: "已限流")
    let summaryBalance = BillingBalance(percentLimits: [
        BillingPercentLimit(id: "window:rolling", title: "5 小时", remainingFraction: 0.98, resetsAt: nil),
        BillingPercentLimit(id: "window:weekly", title: "每周", remainingFraction: 0.99, resetsAt: nil),
        monthlyLimited,
    ])
    assertEqual(formatBalanceSummary(summaryBalance), "5 小时 98% · 每周 99% · 每月 0% 已限流",
                "余额摘要拼接")
    assertEqual(formatBalanceSummary(BillingBalance(purchasedUSD: 25)), "可用 $25", "仅金额时的摘要")
    assertEqual(formatBalanceSummary(BillingBalance()), "无额度数据", "空余额摘要")
}

// MARK: - 刷新节流

/// 每 provider 独立节流：全局下限 60 秒，provider 可要求更长（OpenCode Go 5 分钟）
private func testBillingRefreshScheduler() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    assertEqual(BillingRefreshScheduler.interval(providerMinimum: 0), 60, "未声明时用全局下限")
    assertEqual(BillingRefreshScheduler.interval(providerMinimum: 300), 300, "provider 可要求更长")
    assertEqual(BillingRefreshScheduler.interval(providerMinimum: 10), 60, "短于全局下限时被抬高")

    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: nil,
                                              providerMinimum: 0, force: false), true,
                "从未刷新过时立即到期")
    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: now.addingTimeInterval(-59),
                                              providerMinimum: 0, force: false), false,
                "59 秒未到期")
    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: now.addingTimeInterval(-60),
                                              providerMinimum: 0, force: false), true,
                "满 60 秒到期")
    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: now.addingTimeInterval(-299),
                                              providerMinimum: 300, force: false), false,
                "provider 长间隔内未到期")
    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: now.addingTimeInterval(-300),
                                              providerMinimum: 300, force: false), true,
                "provider 间隔到期")
    assertEqual(BillingRefreshScheduler.isDue(now: now, lastAttempt: now,
                                              providerMinimum: 300, force: true), true,
                "强制刷新跳过所有节流")
}

// MARK: - 额度格排版规则

/// 三列窄格必须让角标分行（86pt 放不下「已限流 · 10/26 08:00 重置」）
private func testBillingLimitLayout() {
    assertEqual(BillingLimitLayout.maxColumns, 3, "额度格最多三列")
    assertEqual(BillingLimitLayout.isCompact(columnCount: 1), false, "单列不窄")
    assertEqual(BillingLimitLayout.isCompact(columnCount: 2), false, "双列不窄")
    assertEqual(BillingLimitLayout.isCompact(columnCount: 3), true, "三列窄格")
    assertEqual(BillingLimitLayout.isCompact(columnCount: 4), true, "超过上限仍按窄格处理")
    assertEqual(BillingLimitLayout.inlineBadge("已限流"), "已限流 ·", "同行角标带间隔点")
    assertEqual(BillingLimitLayout.inlineBadge(""), " ·", "空角标只留间隔点（不会出现，防御）")
}