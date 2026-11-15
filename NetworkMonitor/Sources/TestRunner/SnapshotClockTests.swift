import Foundation
import NetworkMonitorCore

// MARK: - 快照冻结时钟（NM_SNAPSHOT_FREEZE）
//
// 存在理由：Token / 额度页此前无法做逐像素回归 —— 同一份代码连跑两次差异约 10%，
// 因为页面里有实时数值与时钟。冻结通道把时间收敛到 SnapshotClock，本文件守住它的语义：
// 缺省回落真实时钟、`now` 对齐整分钟、epoch 秒固定值、非法输入明确失败。
//
// 冻结 fixture 本体在 app target（`Debug/SnapshotFreeze.swift`，仅 DEBUG），
// TestRunner 只 link Core，故这里只断言时钟与日期键口径；fixture 的一致性由
// 「冻结模式连跑两次 PNG 的 sha256 相同」在真实进程里自证。

private func testSnapshotClockParsing() {
    assertEqual(SnapshotClock.parse(nil) == nil, true, "缺省应为未冻结")
    assertEqual(SnapshotClock.parse("") == nil, true, "空串应为未冻结")
    assertEqual(SnapshotClock.parse("abc") == nil, true, "非法输入应为未冻结")
    assertEqual(SnapshotClock.parse("1e400") == nil, true, "无穷大应为未冻结")

    let reference = Date(timeIntervalSince1970: 1_794_729_600 + 47)   // 整分钟后 47 秒
    guard let aligned = SnapshotClock.parse("now", reference: reference) else {
        assertNotNil(nil as Date?, "now 形式应可解析")
        return
    }
    assertEqual(aligned.timeIntervalSince1970, 1_794_729_600.0, "now 应对齐到整分钟")

    guard let fixed = SnapshotClock.parse("1794729600") else {
        assertNotNil(nil as Date?, "epoch 秒应可解析")
        return
    }
    assertEqual(fixed.timeIntervalSince1970, 1_794_729_600.0, "epoch 秒应精确还原")
}

private func testSnapshotClockLiveFallback() {
    // 未设环境变量时 now 必须等价于真实时钟（进程内前后两次取值的差应极小）
    guard !SnapshotClock.isFrozen else { return }
    let first = SnapshotClock.now
    let second = SnapshotClock.now
    assertEqual(abs(second.timeIntervalSince(first)) < 1.0, true, "未冻结时 now 应跟随真实时间")
}

private func testSnapshotFrozenDayKeyStability() {
    // 同一冻结时刻 → 同一日期键；跨分钟不漂移（否则「近 7 天」标签会随运行时刻抖动）
    let clock = Date(timeIntervalSince1970: 1_794_729_600)
    let key = HarnessTokenTimeWindow.dayKey(for: clock)
    assertEqual(HarnessTokenTimeWindow.dayKey(for: clock), key, "同一时刻的日期键必须一致")
    assertEqual(HarnessTokenTimeWindow.dayKey(for: clock.addingTimeInterval(60)), key,
                "跨分钟不应改变日期键")
}

func runSnapshotClockTests() {
    testSnapshotClockParsing()
    testSnapshotClockLiveFallback()
    testSnapshotFrozenDayKeyStability()
    print("✓ 快照冻结时钟（缺省回落 / now 对齐整分钟 / epoch 固定 / 日期键不漂移）")
}
