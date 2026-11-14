import Foundation
import NetworkMonitorCore

// MARK: - 缩略图失败重试策略（A2 验收）

/// 覆盖第三批规格 5 节 A2 的全部断言项：冷却期内 / 过冷却 / 达 maxAttempts 终态 /
/// markSucceeded 清空 / reset 清空，另加时间可注入、非法入参与默认值三处边界。
func runClipboardThumbnailRetryPolicyTests() {
    print("🧪 Testing Clipboard thumbnail retry policy...")

    // 1) 默认值：冷却 30s、最多 3 次（含首次）
    assertEqual(ClipboardThumbnailRetryPolicy.defaultCooldown, 30, "默认冷却 30s")
    assertEqual(ClipboardThumbnailRetryPolicy.defaultMaxAttempts, 3, "默认最多 3 次")
    var policy = ClipboardThumbnailRetryPolicy()
    assertEqual(policy.cooldown, 30, "默认构造冷却 30s")
    assertEqual(policy.maxAttempts, 3, "默认构造最多 3 次")
    assertEqual(ClipboardThumbnailRetryPolicy(cooldown: 0).cooldown, 0, "冷却 0 合法（立即重试）")
    assertEqual(ClipboardThumbnailRetryPolicy(cooldown: -5).cooldown, 0, "负冷却归一化为 0")
    assertEqual(ClipboardThumbnailRetryPolicy(maxAttempts: 0).maxAttempts, 3, "次数 0 归一化为默认值")
    assertEqual(ClipboardThumbnailRetryPolicy(maxAttempts: -2).maxAttempts, 3, "次数负数归一化为默认值")

    // 2) 从未失败：允许重试，剩余等待 0
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    assertEqual(policy.shouldRetry(hash: "h1", now: base), true, "从未失败 → 可重试")
    assertEqual(policy.failureCount(hash: "h1"), 0, "从未失败 → 失败次数 0")
    assertEqual(policy.retryDelay(hash: "h1", now: base), 0, "从未失败 → 无等待")

    // 3) 冷却期内不再尝试；跨过冷却边界即可重试（边界判定用 >=）
    policy.markFailed(hash: "h1", now: base)
    assertEqual(policy.failureCount(hash: "h1"), 1, "记一次失败")
    assertEqual(policy.shouldRetry(hash: "h1", now: base), false, "冷却期内（0s）不可重试")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(29)), false,
                "冷却期内（29s）不可重试")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(30)), true,
                "恰好到 30s 边界允许重试")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(31)), true,
                "超过冷却时间允许重试")
    assertEqual(policy.retryDelay(hash: "h1", now: base), 30, "刚失败时剩余冷却 30s")
    assertEqual(policy.retryDelay(hash: "h1", now: base.addingTimeInterval(10)), 20,
                "已过 10s 时剩余冷却 20s")
    assertEqual(policy.retryDelay(hash: "h1", now: base.addingTimeInterval(30)), 0,
                "冷却结束后剩余等待归零")

    // 4) 失败累加：每次失败都刷新时间戳，冷却从最后一次失败重新计时
    policy.markFailed(hash: "h1", now: base.addingTimeInterval(40))
    assertEqual(policy.failureCount(hash: "h1"), 2, "第二次失败累计为 2")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(60)), false,
                "冷却从最后一次失败重新计时")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(70)), true,
                "第二次失败后过冷却仍允许重试")

    // 5) 达 maxAttempts 转终态：第 3 次失败后无论如何都不再重试
    policy.markFailed(hash: "h1", now: base.addingTimeInterval(80))
    assertEqual(policy.failureCount(hash: "h1"), 3, "第三次失败累计为 3")
    assertEqual(policy.isExhausted(hash: "h1"), true, "达到次数上限即终态")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(1_000)), false,
                "终态后即使是极远的未来也不再重试")
    assertEqual(policy.retryDelay(hash: "h1", now: base.addingTimeInterval(1_000)), nil,
                "终态不再排期（剩余等待为 nil）")
    // 终态后继续记失败不改变结论，也不会虚增计数
    policy.markFailed(hash: "h1", now: base.addingTimeInterval(2_000))
    assertEqual(policy.failureCount(hash: "h1"), 3, "终态后计数不再增长")
    assertEqual(policy.shouldRetry(hash: "h1", now: base.addingTimeInterval(3_000)), false,
                "终态后再记失败仍为终态")

    // 6) markSucceeded 清空该哈希全部失败记录（其他哈希不受影响）
    var scoped = ClipboardThumbnailRetryPolicy()
    scoped.markFailed(hash: "a", now: base)
    scoped.markFailed(hash: "a", now: base)
    scoped.markFailed(hash: "b", now: base)
    assertEqual(scoped.failureCount(hash: "a"), 2, "a 累计 2 次")
    scoped.markSucceeded(hash: "a")
    assertEqual(scoped.failureCount(hash: "a"), 0, "markSucceeded 清空 a 的失败记录")
    assertEqual(scoped.shouldRetry(hash: "a", now: base), true, "成功后立即可再次重试")
    assertEqual(scoped.isExhausted(hash: "a"), false, "成功后不再是终态")
    assertEqual(scoped.failureCount(hash: "b"), 1, "其他哈希的失败记录不受影响")
    assertEqual(scoped.shouldRetry(hash: "b", now: base), false, "其他哈希仍处于冷却期")

    // 7) reset 清空全部记录
    scoped.markFailed(hash: "a", now: base)
    scoped.markFailed(hash: "a", now: base)
    scoped.markFailed(hash: "a", now: base)
    assertEqual(scoped.isExhausted(hash: "a"), true, "reset 前 a 已是终态")
    scoped.reset()
    assertEqual(scoped.failureCount(hash: "a"), 0, "reset 后 a 失败记录清空")
    assertEqual(scoped.failureCount(hash: "b"), 0, "reset 后 b 失败记录清空")
    assertEqual(scoped.shouldRetry(hash: "a", now: base), true, "reset 后立即可重试")
    assertEqual(scoped.isExhausted(hash: "a"), false, "reset 后不再是终态")

    // 8) 非法入参：空白 hash 一律不记、不放行（空键会让所有条目共用一个记录）
    var blankPolicy = ClipboardThumbnailRetryPolicy()
    assertEqual(blankPolicy.shouldRetry(hash: "   ", now: base), false, "空白 hash 不允许重试")
    assertEqual(blankPolicy.retryDelay(hash: "", now: base), nil, "空白 hash 不排期")
    blankPolicy.markFailed(hash: "", now: base)
    blankPolicy.markFailed(hash: "  ", now: base)
    assertEqual(blankPolicy.failureCount(hash: ""), 0, "空白 hash 不产生失败记录")
    blankPolicy.markSucceeded(hash: "")
    assertEqual(blankPolicy.failureCount(hash: "x"), 0, "空白 hash 的成功记录无副作用")

    // 9) hash 归一化：前后空白视为同一哈希
    var normalized = ClipboardThumbnailRetryPolicy()
    normalized.markFailed(hash: "  hh  ", now: base)
    assertEqual(normalized.failureCount(hash: "hh"), 1, "带空白记的失败按归一化后命中")
    assertEqual(normalized.shouldRetry(hash: "hh", now: base), false, "归一化后同处冷却期")

    print("✅ Clipboard 缩略图重试策略 works")
}
