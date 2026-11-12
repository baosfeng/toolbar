import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板动态轮询调度（Core 纯函数）

/// 覆盖验收标准 B 组：三档边界 / 前台条件 / 归一化 / 停止后不再重排
///
/// 说明：`PasteboardWatcher` 的「停止后不再 tick」由 `ClipboardPollSchedule.nextInterval(isRunning:)`
/// 在纯函数层表达——采集器每次 tick 只调这一个入口，isRunning 为 false 时恒返回 nil（不再排下一次）。
func runClipboardPollScheduleTests() {
    print("🧪 Testing Clipboard poll schedule (dynamic interval)...")

    // 1) 档位常量：与既有 500ms 固定轮询对齐的最快档 + 两个慢档
    assertEqual(ClipboardPollSchedule.activeInterval, 0.5, "最快档 0.5s（与历史 500ms 轮询同档）")
    assertEqual(ClipboardPollSchedule.warmInterval, 2.0, "次快档 2.0s")
    assertEqual(ClipboardPollSchedule.idleInterval, 5.0, "最慢档 5.0s")
    assertEqual(ClipboardPollSchedule.activeIdleThreshold, 30, "活跃阈值 30s")
    assertEqual(ClipboardPollSchedule.idleThreshold, 300, "空闲阈值 300s")

    // 2) 三档边界（设计规格 2.2 第 1 条）
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 0, isAppActive: true), 0.5, "0s 且前台 → 最快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 29.9, isAppActive: true), 0.5, "29.9s 且前台 → 最快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 30, isAppActive: true), 2.0, "恰好 30s 不满足 <30，落次快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 299.9, isAppActive: true), 2.0, "299.9s 仍在次快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 300, isAppActive: true), 5.0, "恰好 300s 落最慢档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 10_000, isAppActive: true), 5.0, "长时间空闲仍是最慢档（不会更慢）")

    // 3) 应用非活跃：无论多活跃都不进最快档（前台是硬条件）
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 0, isAppActive: false), 2.0, "非前台 0s → 次快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 29.9, isAppActive: false), 2.0, "非前台 29.9s → 次快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 300, isAppActive: false), 5.0, "非前台长时间空闲 → 最慢档")
    // 前台但用户已停止操作：同样落慢档（isAppActive 不足以单独决定档位）
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: 60, isAppActive: true), 2.0, "前台但空闲 60s → 次快档")

    // 4) 归一化：负数 / NaN / 正负无穷一律按 0 处理（走最快档，宁可多轮询不漏采）
    assertEqual(ClipboardPollSchedule.normalizedIdleSeconds(-5), 0, "负数归一为 0")
    assertEqual(ClipboardPollSchedule.normalizedIdleSeconds(.nan), 0, "NaN 归一为 0")
    assertEqual(ClipboardPollSchedule.normalizedIdleSeconds(.infinity), 0, "正无穷归一为 0")
    assertEqual(ClipboardPollSchedule.normalizedIdleSeconds(-.infinity), 0, "负无穷归一为 0")
    assertEqual(ClipboardPollSchedule.normalizedIdleSeconds(12), 12, "合法秒数原样保留")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: -5, isAppActive: true), 0.5, "负秒数走最快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: .nan, isAppActive: true), 0.5, "NaN 走最快档")
    assertEqual(ClipboardPollSchedule.interval(idleSeconds: .infinity, isAppActive: true), 0.5, "无穷走最快档")

    // 5) 链式重排入口：停止后恒为 nil（不再排下一次 tick）
    assertEqual(ClipboardPollSchedule.nextInterval(isRunning: false, idleSeconds: 0, isAppActive: true), nil, "已停止时不再重排")
    assertEqual(ClipboardPollSchedule.nextInterval(isRunning: false, idleSeconds: .nan, isAppActive: true), nil, "已停止 + 非法入参仍不重排")
    assertEqual(ClipboardPollSchedule.nextInterval(isRunning: true, idleSeconds: 0, isAppActive: true), 0.5, "运行中活跃 → 最快档")
    assertEqual(ClipboardPollSchedule.nextInterval(isRunning: true, idleSeconds: 400, isAppActive: false), 5.0, "运行中长时间空闲 → 最慢档")

    // 6) 重排入口与 interval 同源（入口只多一层 isRunning 门禁，不改档位口径）
    for (idle, active) in [(0.0, true), (29.9, true), (30.0, false), (120.0, true), (299.9, false), (300.0, true)] {
        assertEqual(ClipboardPollSchedule.nextInterval(isRunning: true, idleSeconds: idle, isAppActive: active),
                    ClipboardPollSchedule.interval(idleSeconds: idle, isAppActive: active),
                    "nextInterval 与 interval 同源（idle=\(idle) active=\(active)）")
    }

    // 7) 单调性：活跃度越高不会更慢（严禁「越闲轮询越勤」这类反向档位）
    let samples: [TimeInterval] = [0, 10, 29.9, 30, 100, 299.9, 300, 3_600]
    var previous = ClipboardPollSchedule.interval(idleSeconds: samples[0], isAppActive: false)
    for idle in samples.dropFirst() {
        let current = ClipboardPollSchedule.interval(idleSeconds: idle, isAppActive: false)
        assertEqual(current >= previous, true, "间隔随空闲时间单调不减（idle=\(idle)）")
        previous = current
    }

    print("✅ Clipboard 动态轮询调度 works")
}
