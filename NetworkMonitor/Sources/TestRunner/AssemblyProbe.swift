import Foundation
import NetworkMonitorUI

// MARK: - 装配自证探针（--assembly-probe）

/// 打印装配的真实结果：拓扑执行顺序、停止逆序，以及两类声明错误的失败文案
///
/// 与测试的区别：测试断言的是**期望**，这里打印的是**实现此刻的实际输出**，
/// 用于验收时肉眼对照「改造前 vs 改造后」的顺序表，以及确认负向输入确实启动即失败。
func runAssemblyProbe() {
    print("=== 拓扑执行顺序（改造后实际顺序）===")
    switch AppAssemblyPlan.resolvedStartOrder() {
    case .success(let order):
        for (index, name) in order.enumerated() {
            let legacy = index < AppAssemblyPlan.legacyStartOrder.count
                ? AppAssemblyPlan.legacyStartOrder[index] : "（改造前无此项）"
            let same = name == legacy ? "相同" : "不同"
            print(String(format: "%2d. %-12@ | 改造前：%-12@ | %@",
                         index + 1,
                         name as NSString,
                         legacy as NSString,
                         same as NSString))
        }
        print("--- 停止逆序（装配器调用 teardown 的顺序）---")
        print(AppAssemblyPlan.resolvedTeardownOrder(order).joined(separator: " → "))
        print("--- 改造前 stop() 手写顺序 ---")
        print(AppAssemblyPlan.legacyTeardownOrder.joined(separator: " → "))
    case .failure(let error):
        print("声明表有错：\(error.message)")
    }

    print("")
    print("=== 负向验证：缺依赖 ===")
    let missing: [AssembleStageSpec] = [
        AssembleStageSpec(name: "剪贴板", requires: ["数据库", "通知与音效"]),
        AssembleStageSpec(name: "数据库"),
    ]
    switch AssembleTopology.plan(missing) {
    case .success(let order):
        print("❌ 未失败（意外）：\(order)")
    case .failure(let error):
        print("✅ 启动即失败：\(error.message)")
    }

    print("")
    print("=== 负向验证：成环 ===")
    let cyclic: [AssembleStageSpec] = [
        AssembleStageSpec(name: "额度", requires: ["设置窗口"]),
        AssembleStageSpec(name: "设置窗口", requires: ["额度"]),
    ]
    switch AssembleTopology.plan(cyclic) {
    case .success(let order):
        print("❌ 未失败（意外）：\(order)")
    case .failure(let error):
        print("✅ 启动即失败：\(error.message)")
    }

    print("")
    print("=== 负向验证：重名 ===")
    let duplicated: [AssembleStageSpec] = [
        AssembleStageSpec(name: "数据库"),
        AssembleStageSpec(name: "数据库"),
    ]
    switch AssembleTopology.plan(duplicated) {
    case .success(let order):
        print("❌ 未失败（意外）：\(order)")
    case .failure(let error):
        print("✅ 启动即失败：\(error.message)")
    }
}
