import Foundation
import NetworkMonitorUI

// MARK: - 最新请求闸门（异步读：只接受最新一次结果）

func runLatestRequestGateTests() {
    print("🧪 Testing 最新请求闸门...")
    var gate = LatestRequestGate()
    assertEqual(gate.accepts(0), false, "还没有请求时序号 0 不被接受")
    let first = gate.next()
    assertEqual(first, 1, "首个请求序号为 1")
    assertEqual(gate.accepts(first), true, "最新请求被接受")
    let second = gate.next()
    assertEqual(gate.accepts(first), false, "旧请求结果被丢弃（不会覆盖新数据）")
    assertEqual(gate.accepts(second), true, "新请求被接受")
    gate.invalidate()
    assertEqual(gate.accepts(second), false, "作废后在途请求一律丢弃")
    let third = gate.next()
    assertEqual(gate.accepts(third), true, "作废后新请求仍被接受")
}
