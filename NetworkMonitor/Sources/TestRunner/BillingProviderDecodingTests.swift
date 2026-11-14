import Foundation
import NetworkMonitorCore

// MARK: - 三家新 provider 的解码

/// 覆盖 Claude / Codex / Cursor 的真实响应结构与边界样本。
///
/// 样本按调研报告 §2 的字段清单构造（Claude `/api/oauth/usage`、Codex `wham/usage`、
/// Cursor `/api/usage-summary`），字段名与真实响应一致；三家都是非公开端点，
/// 所以「正常数据能映射」与「接口变更时退回可自愈提示」同等重要。
/// 失败姿态（401 / 403 / 429 / 5xx / 凭据清洗）见 BillingProviderFailureTests.swift。
func runBillingProviderDecodingTests() {
    print("\n🧪 Testing Claude 额度解码...")
    testClaudeDecoding()

    print("\n🧪 Testing Codex 额度解码...")
    testCodexDecoding()

    print("\n🧪 Testing Cursor 额度解码...")
    testCursorDecoding()

    runBillingProviderFailureTests()

    print("✅ Billing 三家 provider 解码 works")
}

// MARK: - Claude

private func testClaudeDecoding() {
    let sample = """
    {
      "five_hour": {"utilization": 42.5, "resets_at": "2026-11-14T15:00:00.000Z"},
      "seven_day": {"utilization": 78.0, "resets_at": "2026-11-20T08:00:00+00:00"},
      "seven_day_sonnet": {"utilization": 10.0, "resets_at": "2026-11-20T08:00:00+00:00"},
      "seven_day_opus": null,
      "extra_usage": {"is_enabled": true, "monthly_limit": 2000, "used_credits": 350,
                      "utilization": 17.5, "currency": "USD"}
    }
    """.data(using: .utf8)!
    do {
        let balance = try ClaudeBillingDecoding.decodeBalance(from: sample)
        let limits = balance.percentLimits
        assertEqual(limits.map(\.id),
                    ["claude-session", "claude-weekly", "claude-weekly-sonnet", "claude-extra"],
                    "窗口按白名单顺序映射，null 窗口被跳过")
        let session = limits.first { $0.id == "claude-session" }!
        assertEqual(abs(session.remainingFraction - 0.575) < 0.0001, true, "已用 42.5% → 剩余 57.5%")
        assertEqual(session.window?.kind ?? .custom, .session, "5 小时窗口归为会话窗口")
        assertEqual(session.window?.duration ?? 0, 18_000, "会话窗口 18000 秒")
        assertNotNil(session.resetsAt, "会话窗口有重置时刻")
        let weekly = limits.first { $0.id == "claude-weekly" }!
        assertEqual(weekly.window?.kind ?? .custom, .weekly, "周窗口种类")
        assertEqual(weekly.window?.title ?? "", "每周", "周窗口标题")
        assertEqual(abs(weekly.remainingFraction - 0.22) < 0.0001, true, "周已用 78% → 剩余 22%")
        let extra = limits.first { $0.id == "claude-extra" }!
        assertEqual(extra.unitLabel ?? "", "USD", "额外用量单位来自 currency")
        assertEqual(extra.hasAmountDetail, true, "额外用量带绝对值明细")
        assertEqual(abs((extra.remainingFraction - 0.825)) < 0.0001, true, "额外用量剩余比例")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "Claude 真实样本解码")
    }

    let onlyWeekly = """
    {"seven_day": {"utilization": 100, "resets_at": "2026-11-20T08:00:00.000Z"}}
    """.data(using: .utf8)!
    let weeklyBalance = try? ClaudeBillingDecoding.decodeBalance(from: onlyWeekly)
    assertEqual(weeklyBalance?.percentLimits.count ?? 0, 1, "只有周窗口时只产出一条")
    assertEqual(weeklyBalance?.percentLimits.first?.remainingFraction ?? 1, 0, "已用 100% → 剩余 0")

    // Free 计划：两个窗口都是 null → 解析失败而不是「空余额」
    let freePlan = """
    {"five_hour": null, "seven_day": null}
    """.data(using: .utf8)!
    assertEqual(billingErrorMessage { _ = try ClaudeBillingDecoding.decodeBalance(from: freePlan) },
                "响应里没有额度窗口（可能是非订阅账号，或接口已变更）",
                "无窗口时给可自愈提示")

    // 脏数据：utilization 越界 / 负数被钳制
    let dirty = """
    {"five_hour": {"utilization": 130, "resets_at": "2026-11-14T15:00:00.000Z"},
     "seven_day": {"utilization": -5, "resets_at": "2026-11-20T08:00:00.000Z"}}
    """.data(using: .utf8)!
    let dirtyBalance = try? ClaudeBillingDecoding.decodeBalance(from: dirty)
    assertEqual(dirtyBalance?.percentLimits.first { $0.id == "claude-session" }?.remainingFraction ?? 1, 0,
                "已用 >100% 钳制到剩余 0")
    assertEqual(dirtyBalance?.percentLimits.first { $0.id == "claude-weekly" }?.remainingFraction ?? 0, 1,
                "已用负数钳制到剩余 100%")

    assertEqual(billingErrorMessage { _ = try ClaudeBillingDecoding.decodeBalance(from: Data("<html>".utf8)) },
                "响应不是合法的 Claude 额度 JSON（接口可能已变更）", "非 JSON 报解析失败")
}

// MARK: - Codex

private func testCodexDecoding() {
    let sample = """
    {
      "plan_type": "plus",
      "rate_limit": {
        "allowed": true,
        "limit_reached": false,
        "primary_window": {"used_percent": 12, "limit_window_seconds": 18000,
                           "reset_after_seconds": 3600, "reset_at": 1799999999},
        "secondary_window": {"used_percent": 55, "limit_window_seconds": 604800,
                             "reset_after_seconds": 200000, "reset_at": 1800500000}
      },
      "additional_rate_limits": [
        {"limit_name": "gpt-5-spark", "primary_window": {"used_percent": 20,
          "limit_window_seconds": 18000, "reset_at": 1800000000}}
      ]
    }
    """.data(using: .utf8)!
    do {
        let balance = try CodexBillingDecoding.decodeBalance(from: sample)
        let limits = balance.percentLimits
        assertEqual(limits.map(\.id), ["codex-session", "codex-weekly", "codex-extra-gpt-5-spark"],
                    "主 / 次 / 附加窗口按序映射")
        let session = limits[0]
        assertEqual(session.title, "5 小时", "窗口标题按 limit_window_seconds 推断")
        assertEqual(session.window?.kind ?? .custom, .session, "18000 秒归为会话窗口")
        assertEqual(abs(session.remainingFraction - 0.88) < 0.0001, true, "已用 12% → 剩余 88%")
        assertEqual(session.resetsAt?.timeIntervalSince1970 ?? 0, 1_799_999_999, "reset_at 为 epoch 秒")
        let weekly = limits[1]
        assertEqual(weekly.window?.kind ?? .custom, .weekly, "604800 秒归为周窗口")
        assertEqual(weekly.title, "每周", "周窗口标题")
        assertEqual(weekly.badge == nil, true, "未限流无角标")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "Codex 真实样本解码")
    }

    let limited = """
    {"plan_type": "plus", "rate_limit": {"allowed": false, "limit_reached": true,
      "primary_window": {"used_percent": 100, "limit_window_seconds": 18000, "reset_at": 1799999999}}}
    """.data(using: .utf8)!
    let limitedBalance = try? CodexBillingDecoding.decodeBalance(from: limited)
    assertEqual(limitedBalance?.percentLimits.first?.remainingFraction ?? 1, 0, "限流时剩余归零")
    assertEqual(limitedBalance?.percentLimits.first?.badge ?? "", "已限流", "限流角标")

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let relative = """
    {"rate_limit": {"primary_window": {"used_percent": 50, "limit_window_seconds": 18000,
      "reset_after_seconds": 7200}}}
    """.data(using: .utf8)!
    let relativeBalance = try? CodexBillingDecoding.decodeBalance(from: relative, now: now)
    assertEqual(relativeBalance?.percentLimits.first?.resetsAt?.timeIntervalSince1970 ?? 0,
                1_800_007_200, "reset_after_seconds 按基准时刻换算")

    assertEqual(billingErrorMessage { _ = try CodexBillingDecoding.decodeBalance(from: Data("{}".utf8)) },
                "响应里没有额度窗口（接口可能已变更）", "缺 rate_limit 报解析失败")
    assertEqual(billingErrorMessage { _ = try CodexBillingDecoding.decodeBalance(from: Data("not json".utf8)) },
                "响应不是合法的 Codex 额度 JSON（接口可能已变更）", "非 JSON 报解析失败")
}

// MARK: - Cursor

private func testCursorDecoding() {
    let sample = """
    {
      "billingCycleStart": "2026-11-01T00:00:00.000Z",
      "billingCycleEnd": "2026-12-01T00:00:00.000Z",
      "membershipType": "pro",
      "limitType": "user",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {"used": 1200, "limit": 2000, "totalPercentUsed": 60,
                 "autoPercentUsed": 40, "apiPercentUsed": 20},
        "onDemand": {"used": 500, "limit": 5000},
        "overall": {"used": 0, "limit": 0}
      },
      "teamUsage": {"pooled": {"used": 0, "limit": 0}, "onDemand": {"used": 0, "limit": 0}}
    }
    """.data(using: .utf8)!
    do {
        let balance = try CursorBillingDecoding.decodeBalance(from: sample)
        let limits = balance.percentLimits
        assertEqual(limits.map(\.id), ["cursor-plan", "cursor-on-demand"], "计划 + 按量付费两行")
        let plan = limits[0]
        assertEqual(plan.title, "本月", "计划窗口标题")
        assertEqual(abs(plan.remainingFraction - 0.4) < 0.0001, true, "totalPercentUsed 60 → 剩余 40%")
        assertEqual(plan.window?.kind ?? .custom, .monthly, "账单周期归为月窗口")
        assertNotNil(plan.resetsAt, "月窗口有重置时刻")
        assertEqual(plan.unitLabel ?? "", "USD", "金额单位美元")
        assertEqual(plan.limitAmount ?? 0, 20, "2000 分 → 20 美元")
        let onDemand = limits[1]
        assertEqual(onDemand.title, "按量付费", "按量付费标题")
        assertEqual(abs(onDemand.remainingFraction - 0.9) < 0.0001, true, "按量已用 500/5000 → 剩余 90%")
    } catch {
        assertEqual("抛错：\(error)", "不应抛错", "Cursor 真实样本解码")
    }

    let unlimited = """
    {"billingCycleEnd": "2026-12-01T00:00:00.000Z", "isUnlimited": true,
     "individualUsage": {"plan": {"used": 0, "limit": 0}}}
    """.data(using: .utf8)!
    let unlimitedBalance = try? CursorBillingDecoding.decodeBalance(from: unlimited)
    assertEqual(unlimitedBalance?.percentLimits.first?.remainingFraction ?? 0, 1, "无限制计划剩余 100%")
    assertEqual(unlimitedBalance?.percentLimits.first?.badge ?? "", "无限制", "无限制角标")

    let teamOverall = """
    {"billingCycleEnd": "2026-12-01T00:00:00.000Z",
     "individualUsage": {"overall": {"used": 2500, "limit": 10000},
                         "plan": {"used": 100, "limit": 2000, "totalPercentUsed": 5}}}
    """.data(using: .utf8)!
    let overallBalance = try? CursorBillingDecoding.decodeBalance(from: teamOverall)
    assertEqual(overallBalance?.percentLimits.first?.title ?? "", "个人额度", "统筹上限优先")
    assertEqual(abs((overallBalance?.percentLimits.first?.remainingFraction ?? 0) - 0.75) < 0.0001, true,
                "统筹上限已用 25% → 剩余 75%")

    assertEqual(billingErrorMessage { _ = try CursorBillingDecoding.decodeBalance(from: Data("{}".utf8)) },
                "响应里没有额度数据（接口可能已变更）", "空对象报解析失败")
    assertEqual(billingErrorMessage { _ = try CursorBillingDecoding.decodeBalance(from: Data("null".utf8)) },
                "响应不是合法的 Cursor 额度 JSON（接口可能已变更）", "非对象报解析失败")
}
