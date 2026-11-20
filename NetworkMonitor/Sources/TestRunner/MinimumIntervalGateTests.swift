import Foundation
import NetworkMonitorCore

// MARK: - 最小间隔节流原语

func runMinimumIntervalGateTests() {
    print("🧪 Testing MinimumIntervalGate...")

    let t0 = Date(timeIntervalSince1970: 1_000_000)
    var gate = MinimumIntervalGate(interval: 0.15)

    // 首次：没有上次放行时刻，恒放行并记录时刻
    assertEqual(gate.lastRunAt == nil, true, "首次调用前没有放行记录")
    assertEqual(gate.shouldRun(now: t0), true, "首次恒放行")
    assertEqual(gate.lastRunAt, t0, "放行后记录本次时刻")

    // 间隔内：拒绝，且不以当前时刻推进（窗口不被高频调用顺延）
    assertEqual(gate.shouldRun(now: t0.addingTimeInterval(0.149)), false, "间隔内（0.149s）拒绝")
    assertEqual(gate.lastRunAt, t0, "拒绝时 lastRunAt 不推进")

    // 跨过间隔：再次放行
    let t1 = t0.addingTimeInterval(5)
    assertEqual(gate.shouldRun(now: t1), true, "远超间隔时放行")
    assertEqual(gate.lastRunAt, t1, "再次放行后记录新时刻")

    // 时钟回退：按放行处理并重置，避免永久卡死
    let rewound = t1.addingTimeInterval(-10)
    assertEqual(gate.shouldRun(now: rewound), true, "时钟回退时放行")
    assertEqual(gate.lastRunAt, rewound, "时钟回退后重置为回退后的时刻")
    assertEqual(gate.shouldRun(now: rewound.addingTimeInterval(0.01)), false,
                "回退后的新窗口照常生效（0.01s 内拒绝）")

    // 边界：用整数秒做闸门，Date 里的小数（如 0.15）有二进制表示误差，不适合断言等号
    var boundaryGate = MinimumIntervalGate(interval: 1)
    let b0 = Date(timeIntervalSince1970: 1_000_000)
    assertEqual(boundaryGate.shouldRun(now: b0), true, "边界用例首次放行")
    assertEqual(boundaryGate.shouldRun(now: b0.addingTimeInterval(0.999999)), false,
                "差一点到间隔仍拒绝")
    assertEqual(boundaryGate.shouldRun(now: b0.addingTimeInterval(1)), true, "恰好等于间隔时放行")
    assertEqual(boundaryGate.lastRunAt, b0.addingTimeInterval(1), "边界放行后记录新时刻")

    // 零间隔：不节流，同一时刻连续放行
    var zeroGate = MinimumIntervalGate(interval: 0)
    assertEqual(zeroGate.shouldRun(now: t0), true, "零间隔首次放行")
    assertEqual(zeroGate.shouldRun(now: t0), true, "零间隔同一时刻再放行")

    // 负间隔：按不节流处理（调用方传负数意图就是每次都跑）
    var negativeGate = MinimumIntervalGate(interval: -1)
    assertEqual(negativeGate.shouldRun(now: t0), true, "负间隔首次放行")
    assertEqual(negativeGate.shouldRun(now: t0), true, "负间隔同一时刻再放行")

    // 默认参数走真实当前时刻：首次仍恒放行
    var defaultNowGate = MinimumIntervalGate(interval: 60)
    assertEqual(defaultNowGate.shouldRun(), true, "默认 now 参数首次放行")
    assertEqual(defaultNowGate.shouldRun(), false, "默认 now 参数间隔内拒绝")
    assertNotNil(defaultNowGate.lastRunAt, "默认 now 参数也记录放行时刻")

    // 值语义：拷贝互不影响（跨隔离域复制时不会串状态）
    var original = MinimumIntervalGate(interval: 1)
    _ = original.shouldRun(now: t0)
    var copy = original
    assertEqual(copy.shouldRun(now: t0.addingTimeInterval(2)), true, "拷贝可独立放行")
    assertEqual(original.lastRunAt, t0, "原闸门状态不被拷贝改变")
}
