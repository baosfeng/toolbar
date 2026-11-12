import NetworkMonitorUI

// MARK: - 面板高度预算（五页补齐页头 / 状态带后仍不触发滚动）

func runPaneHeightBudgetTests() {
    print("\n🧪 Testing PaneHeightBudget...")
    do {
        // 固定件合计：顶 10 + 分页 28 + 间距 12 + 底 12 = 62
        assertEqual(PaneHeightBudget.chromeHeight(hasHeader: false, hasBand: false), 62,
                    "无页头无状态带时固定件合计 62pt")
        // 加页头：+22 +4 = +26 → 88
        assertEqual(PaneHeightBudget.chromeHeight(hasHeader: true, hasBand: false), 88,
                    "加页头 22pt 与 4pt 间距后 88pt")
        // 再加状态带：+4 +20 = +24 → 112
        assertEqual(PaneHeightBudget.chromeHeight(hasHeader: true, hasBand: true), 112,
                    "页头 + 状态带合计 112pt")

        // 内容预算：520 - 112 = 408
        assertEqual(PaneHeightBudget.paneBudget(hasHeader: true, hasBand: true), 408,
                    "五页统一骨架下内容区预算 408pt")
        assertEqual(PaneHeightBudget.paneBudget(hasHeader: false, hasBand: false), 458,
                    "旧骨架（额度 / Token 前）内容区 458pt")

        // 判定：等于预算算装得下（留 0.5pt 浮点余量），超 1pt 算溢出
        assertEqual(PaneHeightBudget.fits(contentHeight: 408, hasHeader: true, hasBand: true), true,
                    "恰好等于预算时判定装得下")
        assertEqual(PaneHeightBudget.fits(contentHeight: 408.4, hasHeader: true, hasBand: true), true,
                    "0.4pt 浮点余量内仍算装得下")
        assertEqual(PaneHeightBudget.fits(contentHeight: 409, hasHeader: true, hasBand: true), false,
                    "超出 1pt 即判溢出")

        // 溢出量：正数 = 超了，负数 = 还有余量
        assertEqual(PaneHeightBudget.overflow(contentHeight: 430, hasHeader: true, hasBand: true), 22,
                    "430pt 内容超预算 22pt")
        assertEqual(PaneHeightBudget.overflow(contentHeight: 380, hasHeader: true, hasBand: true), -28,
                    "380pt 内容仍余 28pt")

        // 收缩条数：固定部分 300pt、行高 28pt、预算 408 → 还能放 3 行（108pt ≤ 108）
        assertEqual(PaneHeightBudget.rowLimit(fixedHeight: 300, rowHeight: 28, desired: 8,
                                              hasHeader: true, hasBand: true), 3,
                    "预算内只放得下 3 个 28pt 行")
        // 固定部分已经超过预算 → 0 行，不得返回负数
        assertEqual(PaneHeightBudget.rowLimit(fixedHeight: 500, rowHeight: 28, desired: 5,
                                              hasHeader: true, hasBand: true), 0,
                    "固定部分超预算时返回 0 行")
        // 数据条数少于可放行数 → 按数据给
        assertEqual(PaneHeightBudget.rowLimit(fixedHeight: 200, rowHeight: 28, desired: 2,
                                              hasHeader: true, hasBand: true), 2,
                    "数据只有 2 条时按数据条数返回")
        // 非法入参不产生除零 / 负值
        assertEqual(PaneHeightBudget.rowLimit(fixedHeight: 0, rowHeight: 0, desired: 5,
                                              hasHeader: true, hasBand: true), 0,
                    "行高 0 时返回 0 行而不是崩溃")
    }
    print("✅ 面板高度预算测试通过")
}
