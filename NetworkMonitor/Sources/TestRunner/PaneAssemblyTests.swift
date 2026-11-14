import Foundation
import NetworkMonitorUI

// MARK: - 面板分页懒装配记账（从 main.swift 拆出）

/// 分页懒装配记账断言 —— 三条验收口径的纯逻辑层（不依赖 AppKit）
///
/// 1. 冷启动只装配当前分页，其余分页为空；
/// 2. 首次切到某页才装配该页；
/// 3. 重复切页不重建（每页装配次数恒为 1）。
func runPaneAssemblyTests() {
    print("\n🧪 Testing PaneAssemblyLedger...")
    do {
        var ledger = PaneAssemblyLedger<String>()
        var created: [String] = []
        // 模拟面板：只有首次装配才「建页」，已装配则复用
        func visit(_ tab: String) {
            if ledger.requestAssembly(tab) { created.append(tab) }
        }

        // 1. 冷启动：只装配首屏，其余五页为空
        visit("network")
        assertEqual(created, ["network"], "冷启动只装配当前分页")
        assertEqual(ledger.assembledCount, 1, "已装配分页数为 1")
        assertEqual(ledger.isAssembled("network"), true, "当前分页已装配")
        assertEqual(ledger.isAssembled("system"), false, "未切到的系统页为空")
        assertEqual(ledger.isAssembled("token"), false, "未切到的 Token 页为空")

        // 2. 首次切到才装配
        visit("system")
        assertEqual(created, ["network", "system"], "首次切到才装配该页")
        assertEqual(ledger.isAssembled("system"), true, "切页后非空")
        assertEqual(ledger.assemblyCount(for: "system"), 1, "首次装配计一次")

        // 3. 切走再切回：不重建、不重复加约束
        visit("network")
        visit("system")
        visit("network")
        assertEqual(created, ["network", "system"], "重复切页不重复创建")
        assertEqual(ledger.assemblyCount(for: "network"), 1, "重复切页后网络页装配次数仍为 1")
        assertEqual(ledger.assemblyCount(for: "system"), 1, "重复切页后系统页装配次数仍为 1")
        assertEqual(ledger.assembledCount, 2, "已装配分页数不因重复切页增加")

        // 4. 六页都切过之后：全部装配，且每页只建一次
        for tab in ["network", "clipboard", "transfer", "credits", "token", "system"] { visit(tab) }
        assertEqual(ledger.assembledCount, 6, "六页都切过之后全部已装配")
        assertEqual(created.count, 6, "每页只创建一次")
        assertEqual(ledger.assemblyCount(for: "credits"), 1, "额度页只创建一次")

        // 5. 未装配页的装配次数为 0（数据转发据此判空跳过），首次请求返回 true
        var fresh = PaneAssemblyLedger<Int>()
        assertEqual(fresh.assembledCount, 0, "新建记账表为空")
        assertEqual(fresh.assemblyCount(for: 3), 0, "未装配分页装配次数为 0")
        assertEqual(fresh.requestAssembly(3), true, "首次请求返回 true（调用方需新建）")
        assertEqual(fresh.requestAssembly(3), false, "再次请求返回 false（调用方复用旧实例）")

        print("✅ PaneAssemblyLedger 分页懒装配记账 works")
    }
}
