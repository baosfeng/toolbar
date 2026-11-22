import Foundation
import NetworkMonitorCore

// MARK: - 自动监控时间口径（设计规格 §5.1）
//
// 覆盖：firstFireDelay / 归一化边界（0 / 负数 / NaN / ∞ / 45 / 60 / 3000）/
// nextFireDate 的三组样例 / 「基准是本轮结束时间」。
// 时间全部自造（固定 epoch），不读系统时钟。

/// 2026-01-05 12:00:00 +08:00（Asia/Shanghai）
private let sampleNoon = Date(timeIntervalSince1970: 1_767_585_600)

/// 固定时区的 HH:mm:ss（时区不可用时回落 autoupdatingCurrent，会让基点自身断言先红）
private func clockText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        ?? TimeZone(secondsFromGMT: 8 * 3600)
        ?? TimeZone.autoupdatingCurrent
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

func runTokenAutoIndexScheduleTests() {
    print("🧪 Testing 自动监控时间口径（首触延迟 / 间隔归一 / nextFireDate 样例）...")

    // 基点自检：后面的「12:05:00」断言依赖它确实是 12:00:00
    assertEqual(clockText(sampleNoon), "12:00:00", "基点：2026-01-05 12:00:00 +08:00")
    assertEqual(TokenAutoIndexSchedule.firstFireDelay, 1, "启动 / 唤醒首触延迟 1s")

    // MARK: nextFireDate 三组样例
    let plusFiveMinutes = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 300)
    assertEqual(clockText(plusFiveMinutes), "12:05:00", "样例 300s：(12:00:00,300) → 12:05:00")
    assertEqual(plusFiveMinutes.timeIntervalSince(sampleNoon), 300, "样例 300s：增量为 300")

    let clampedToOneMinute = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 30)
    assertEqual(clockText(clampedToOneMinute), "12:01:00", "样例 30s：(12:00:00,30) → 12:01:00（下限 60 生效）")
    assertEqual(clampedToOneMinute.timeIntervalSince(sampleNoon), 60, "样例 30s：归一为 60")

    let zeroFallsBack = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 0)
    assertEqual(clockText(zeroFallsBack), "12:05:00", "样例 0s：(12:00:00,0) → 12:05:00（按默认 300）")
    assertEqual(zeroFallsBack.timeIntervalSince(sampleNoon), 300, "样例 0s：归一为 300")

    // 45 → 60（下限夹取的最小可见样例）
    let fortyFive = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 45)
    assertEqual(clockText(fortyFive), "12:01:00", "样例 45s：夹到下限 → 12:01:00")
    assertEqual(fortyFive.timeIntervalSince(sampleNoon), 60, "样例 45s：归一为 60")

    // 3000 → 12:50:00（远大于默认值时不夹上限）
    let fiftyMinutes = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 3000)
    assertEqual(clockText(fiftyMinutes), "12:50:00", "样例 3000s：→ 12:50:00")
    assertEqual(fiftyMinutes.timeIntervalSince(sampleNoon), 3000, "样例 3000s：增量原样")

    // 60 恰好等于下限：保持不变
    assertEqual(TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: 60)
                    .timeIntervalSince(sampleNoon), 60, "样例 60s：下限值原样保留")

    // MARK: 归一化边界（0 / 负数 / NaN / ∞ / 45 / 60 / 3000）
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(0), 300, "归一：0 → 300")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(-1), 300, "归一：负数 → 300")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(-300), 300, "归一：大负数 → 300")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(.nan), 300, "归一：NaN → 300")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(.infinity), 300, "归一：∞ → 300")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(45), 60, "归一：45 → 60")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(59.9), 60, "归一：略低于下限 → 60")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(60), 60, "归一：60 原样")
    assertEqual(TokenAutoIndexSchedule.normalizedInterval(3000), 3000, "归一：3000 原样")

    // 非法间隔同样不能让下一次触发落回过去（不追帧）
    for raw in [0.0, -1.0, TimeInterval.nan, TimeInterval.infinity] as [TimeInterval] {
        let next = TokenAutoIndexSchedule.nextFireDate(after: sampleNoon, interval: raw)
        assertEqual(next > sampleNoon, true, "非法间隔 \(raw)：下一次触发仍在未来")
    }

    // MARK: 基准是「本轮结束」而不是「本轮开始」
    let roundEndedAt = sampleNoon.addingTimeInterval(120)
    let fromEnd = TokenAutoIndexSchedule.nextFireDate(after: roundEndedAt, interval: 60)
    assertEqual(fromEnd.timeIntervalSince(roundEndedAt), 60, "基准：以本轮结束时间加间隔")
    assertEqual(fromEnd.timeIntervalSince(sampleNoon), 180, "基准：结束时间整体后移则下一次也后移")

    print("✅ 自动监控时间口径 works")
}
