import Foundation
import NetworkMonitorCore

// MARK: - 网络速度差分（Core 纯逻辑）

/// 网卡字节计数差分 —— 三条真实踩过的边界各有一组断言：
/// 首帧没有基线不能算增量、计数回退（网卡重置 / 32 位回绕）不能下溢、
/// 网卡消失不能算出负增量。这些以前只能靠真机插拔网卡复现。
func runNetworkSpeedDeltaTests() {
    print("\n🧪 Testing 网络速度差分（首帧 / 回退 / 网卡增删）...")
    testFirstSampleIgnored()
    testNormalGrowth()
    testCounterRollback()
    testInterfaceAdded()
    testInterfaceRemoved()
    testMultipleInterfaces()
    testOverflowSaturates()
    print("✅ 网络速度差分 works")
}

private typealias Counters = [String: (rx: UInt64, tx: UInt64)]

private func testFirstSampleIgnored() {
    let first: Counters = ["en0": (1000, 2000)]
    assertEqual(NetworkSpeedDelta.compute(previous: [:], current: first),
                NetworkSpeedDelta.Bytes(rx: 0, tx: 0),
                "首帧没有基线，增量为 0（不把累计值当成一次增量）")
}

private func testNormalGrowth() {
    let previous: Counters = ["en0": (1000, 2000)]
    let current: Counters = ["en0": (1500, 2600)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: 500, tx: 600),
                "正常增长取差值")
}

private func testCounterRollback() {
    let previous: Counters = ["en0": (5000, 100)]
    let current: Counters = ["en0": (100, 40)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: 100, tx: 40),
                "计数回退按当前值兜底，不下溢成天文数字")
}

private func testInterfaceAdded() {
    let previous: Counters = ["en0": (100, 100)]
    let current: Counters = ["en0": (200, 200), "utun3": (999, 999)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: 100, tx: 100),
                "新网卡首帧不计（没有它的基线）")
}

private func testInterfaceRemoved() {
    let previous: Counters = ["en0": (100, 100), "utun3": (500, 500)]
    let current: Counters = ["en0": (200, 200)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: 100, tx: 100),
                "消失的网卡丢弃，不产生负增量")
}

private func testMultipleInterfaces() {
    let previous: Counters = ["en0": (0, 0), "en1": (10, 10)]
    let current: Counters = ["en0": (300, 400), "en1": (15, 20)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: 305, tx: 410),
                "多网卡求和（Wi-Fi + 有线）")
}

private func testOverflowSaturates() {
    let half = UInt64.max / 2
    let previous: Counters = ["a": (0, 0), "b": (0, 0)]
    let current: Counters = ["a": (half, half), "b": (half, half)]
    assertEqual(NetworkSpeedDelta.compute(previous: previous, current: current),
                NetworkSpeedDelta.Bytes(rx: half &+ half, tx: half &+ half),
                "极端量级用 &+ 求和，不崩")
}
