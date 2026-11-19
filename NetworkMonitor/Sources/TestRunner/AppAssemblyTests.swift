import Foundation
import NetworkMonitorUI

// MARK: - 启动装配（声明 + 拓扑排序）

/// 装配器的判据 —— 顺序、失败、清理三类
///
/// 为什么逐条钉：装配顺序过去只由 `start()` 的代码位置维持，静默错位不会有任何编译错误
/// （典型的「额度链路先于通知与音效」，跑起来只是通知静默不发）。这里把「顺序等价」
/// 「声明错位即失败」变成机器判据。
func runAppAssemblyTests() {
    print("\n🧪 Testing 启动装配（拓扑排序 / 缺依赖 / 成环 / 等价性）...")

    // MARK: 正常路径：声明表本身自洽，且排序结果与改造前手写顺序逐项相同

    let resolved = AppAssemblyPlan.resolvedStartOrder()
    guard case .success(let startOrder) = resolved else {
        assertEqual("声明表应有解", "\(resolved)", "声明表自洽（无重名 / 缺依赖 / 成环）")
        return
    }
    assertEqual(startOrder, AppAssemblyPlan.legacyStartOrder,
                "拓扑执行顺序与改造前手写顺序逐项相同（同层按声明序稳定）")
    assertEqual(startOrder.count, 18, "阶段数量（数据库 … 启动清理）")

    // MARK: 等价性：逐行对照改造前手写顺序（硬编码期望，不读实现里的同一份常量）

    let expectedOrder = [
        "数据库", "网络监控", "流量追踪", "通知与音效", "剪贴板", "截图", "系统权限",
        "局域网互传", "额度", "更新检查", "设置窗口", "屏幕活动", "Token 统计", "系统监控",
        "菜单栏", "定时落盘", "自动更新检查", "启动清理",
    ]
    for (index, name) in expectedOrder.enumerated() {
        assertEqual(startOrder[index], name, "第 \(index + 1) 阶段")
    }

    // MARK: 停止顺序 = 启动顺序的逆序裁剪（带 teardown 的五个阶段）

    assertEqual(AppAssemblyPlan.resolvedTeardownOrder(startOrder), AppAssemblyPlan.legacyTeardownOrder,
                "停止顺序与改造前 stop() 手写逆序逐项相同")
    assertEqual(AppAssemblyPlan.resolvedTeardownOrder(startOrder),
                ["定时落盘", "屏幕活动", "局域网互传", "剪贴板", "数据库"],
                "停止顺序硬编码对照")

    // MARK: 乱序输入 → 按依赖执行

    let shuffled = [
        AssembleStageSpec(name: "c", requires: ["a", "b"]),
        AssembleStageSpec(name: "b", requires: ["a"]),
        AssembleStageSpec(name: "a"),
    ]
    assertEqual(AssembleTopology.plan(shuffled),
                .success(["a", "b", "c"]),
                "乱序输入按 requires 排成 a → b → c")

    // MARK: 同层按声明序稳定

    let siblings = [
        AssembleStageSpec(name: "root"),
        AssembleStageSpec(name: "second", requires: ["root"]),
        AssembleStageSpec(name: "first", requires: ["root"]),
    ]
    assertEqual(AssembleTopology.plan(siblings),
                .success(["root", "second", "first"]),
                "同层互不依赖的阶段保持声明序")

    // MARK: 缺依赖 → 明确失败并给出缺失的名字

    let missing = [
        AssembleStageSpec(name: "clipboard", requires: ["database", "notifications"]),
        AssembleStageSpec(name: "database"),
    ]
    assertEqual(AssembleTopology.plan(missing),
                .failure(.missingDependency(stage: "clipboard", missing: "notifications")),
                "缺依赖判红并点名缺失的阶段")
    assertContains(AssemblePlanError.missingDependency(stage: "clipboard", missing: "notifications").message,
                   "notifications", "失败文案包含缺失依赖名")
    assertContains(AssemblePlanError.missingDependency(stage: "clipboard", missing: "notifications").message,
                   "clipboard", "失败文案包含依赖它的阶段名")

    // MARK: 成环 → 明确失败（列出环上的阶段）

    let cyclic = [
        AssembleStageSpec(name: "a", requires: ["b"]),
        AssembleStageSpec(name: "b", requires: ["a"]),
    ]
    assertEqual(AssembleTopology.plan(cyclic),
                .failure(.cycle(stages: ["a", "b"])),
                "成环判红并列出环上的阶段")
    assertContains(AssemblePlanError.cycle(stages: ["a", "b"]).message, "成环", "成环文案")

    // MARK: 重名 → 明确失败（重名会让依赖静默解析到另一个阶段）

    let duplicated = [AssembleStageSpec(name: "a"), AssembleStageSpec(name: "a")]
    assertEqual(AssembleTopology.plan(duplicated),
                .failure(.duplicateName("a")),
                "阶段重名判红")

    // MARK: 边界：空表 / 单阶段 / 自依赖

    assertEqual(AssembleTopology.plan([]), .success([]), "空声明表排序为空")
    assertEqual(AssembleTopology.plan([AssembleStageSpec(name: "only")]),
                .success(["only"]), "单阶段")
    assertEqual(AssembleTopology.plan([AssembleStageSpec(name: "self", requires: ["self"])]),
                .failure(.cycle(stages: ["self"])), "自依赖即成环")

    // MARK: 声明表内部一致：排序结果无重复；声明序本身即改造前顺序

    assertEqual(Set(startOrder).count, startOrder.count, "排序结果无重复阶段")
    assertEqual(AppAssemblyPlan.declarations.map(\.name), AppAssemblyPlan.legacyStartOrder,
                "声明序本身即改造前顺序（拓扑只是校验，不改顺序）")

    print("✅ 启动装配 works")
}
