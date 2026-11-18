import Foundation
import NetworkMonitorCore

// MARK: - OpenCode Go 窗口字段映射

/// `OpencodeGoWindow → BillingQuotaWindow` 的映射断言。
///
/// 为什么单开一个文件：`OpencodeGoBillingTests.swift` 已接近单文件 15 KiB 上限，
/// 而窗口字段是**另一件事**——它只被恢复通知消费（`BillingAlerts` 用 cycleID
/// 区分「会话窗口重置」与「周 / 月额度重置」），与「已用→剩余换算」互不影响，
/// 因此按职责拆开而不是继续往同一文件里堆。
func runOpencodeGoWindowFieldTests() {
    print("\n🧪 Testing OpenCode Go 窗口字段映射...")
    testOpencodeGoWindowKinds()
    testOpencodeGoWindowSharesResetInstant()
    testOpencodeGoWindowAbsentWithoutReset()
    print("✅ OpenCode Go 窗口字段映射 works")
}

// MARK: - 种类与时长

/// 三窗口种类必须与官方口径一致：5 小时 → 会话、每周 → 每周、每月 → 每月
private func testOpencodeGoWindowKinds() {
    let json = """
    { "usage": {
        "rolling": { "percent": 25, "resetsAt": "2026-10-25T12:00:00Z", "status": "ok" },
        "weekly": { "percent": 12.5, "resetsAt": "2026-10-31T00:00:00Z", "status": "ok" },
        "monthly": { "percent": 100, "resetsAt": "2026-11-24T00:00:00Z", "status": "ok" } } }
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8)) else {
        assertEqual("decode failed", "", "三窗口解码不应失败")
        return
    }
    let limits = balance.percentLimits
    assertEqual(limits.count, 3, "三个窗口各一条限额")

    let rolling = limits[0]
    assertNotNil(rolling.window, "5 小时窗口带 window（恢复通知据此取 cycleID）")
    assertEqual(rolling.window?.kind ?? .custom, .session, "5 小时窗口归为会话窗口")
    assertEqual(rolling.window?.duration ?? 0, 18_000, "会话窗口 18000 秒")

    let weekly = limits[1]
    assertEqual(weekly.window?.kind ?? .custom, .weekly, "周窗口种类")
    assertEqual(weekly.window?.duration ?? 0, 604_800, "周窗口 604800 秒")
    assertEqual(weekly.window?.title ?? "", "每周", "周窗口展示名")

    let monthly = limits[2]
    assertEqual(monthly.window?.kind ?? .custom, .monthly, "月窗口种类")
    assertEqual(monthly.window?.duration ?? 0, 2_592_000, "月窗口 2592000 秒")
    assertEqual(monthly.window?.title ?? "", "每月", "月窗口展示名")

    // 周期标识必须带种类：否则「5 小时重置」与「每周重置」撞同一时刻时无法区分
    assertContains(rolling.window?.cycleID ?? "", "session@", "会话周期标识带种类前缀")
    assertContains(weekly.window?.cycleID ?? "", "weekly@", "周周期标识带种类前缀")
    assertContains(monthly.window?.cycleID ?? "", "monthly@", "月周期标识带种类前缀")
    let cycleIDs = Set(limits.compactMap { $0.window?.cycleID })
    assertEqual(cycleIDs.count, 3, "三个窗口的周期标识互不相同")
}

// MARK: - resetsAt 与 window.resetsAt 同一时刻

/// 契约：有窗口时 `resetsAt` 与 `window.resetsAt` 指向同一时刻（注释见 BillingModels）
private func testOpencodeGoWindowSharesResetInstant() {
    let json = """
    { "usage": { "rolling": { "percent": 30, "resetsAt": "2026-10-25T12:00:00Z", "status": "ok" } } }
    """
    guard let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8)),
          let limit = balance.percentLimits.first else {
        assertEqual("decode failed", "", "单窗口解码不应失败")
        return
    }
    assertEqual(limit.resetsAt, parseISO8601Date("2026-10-25T12:00:00Z"), "resetsAt 按 RFC3339 解析")
    assertEqual(limit.window?.resetsAt, limit.resetsAt, "window.resetsAt 与 resetsAt 同一时刻")

    // 旧字段 resetInSec：换算后的绝对时刻同样要与窗口一致
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let legacy = #"{ "rollingUsage": { "usagePercent": 50, "resetInSec": 3600 } }"#
    let legacyBalance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(legacy.utf8), now: now)
    let legacyLimit = legacyBalance?.percentLimits.first
    assertEqual(legacyLimit?.resetsAt, now.addingTimeInterval(3600),
                "resetInSec 按基准时刻换算成绝对时刻")
    assertEqual(legacyLimit?.window?.resetsAt, legacyLimit?.resetsAt,
                "旧字段形态下窗口重置时刻与 resetsAt 同一时刻")
    assertEqual(legacyLimit?.window?.kind ?? .custom, .session, "旧字段形态同样带窗口种类")
}

// MARK: - 缺重置字段时 window 为 nil

/// 构造不出「何时重置」的窗口就退回无窗口（宁可只给百分比，也不编造重置时刻）
private func testOpencodeGoWindowAbsentWithoutReset() {
    let json = #"{ "usage": { "weekly": { "percent": 50, "status": "ok" } } }"#
    let balance = try? OpencodeGoBillingProvider.decodeBalance(from: Data(json.utf8))
    let limit = balance?.percentLimits.first
    assertNotNil(limit, "窗口在但缺重置字段时仍出限额行")
    assertEqual(limit?.resetsAt == nil, true, "缺重置字段时 resetsAt 为 nil")
    assertEqual(limit?.window == nil, true, "缺重置字段时 window 为 nil")
    assertEqual(limit?.id ?? "", "window:weekly", "稳定 id 不受窗口缺省影响")
}

// MARK: - 测试辅助

/// ISO8601 时间串解析（与 provider 内部实现同口径）
private func parseISO8601Date(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)
}
