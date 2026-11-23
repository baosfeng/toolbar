import Foundation
import NetworkMonitorCore

// MARK: - 菜单栏 Token 指标刷新口径

/// `MenuBarTokenRefresh` 的完整契约：只有菜单栏真的显示 Token 指标时才补拉，且按 60s 节流
///
/// 背景（实测）：默认配置下「后台自动监控」缺键即关，索引只在开面板 / 手动重扫时才跑，
/// 菜单栏的 Token 数字因此长期冻在一个值上（连采 3 分钟恒 713.9M）；点开面板立刻跳到新值。
func runMenuBarTokenRefreshTests() {
    print("🧪 Testing menu bar token refresh...")

    // 1. 指标集合判据：三个 Token 指标任一启用即需要补拉
    assertEqual(MenuBarTokenRefresh.tokenMetrics, [.tokenToday, .tokenCacheHit, .tokenWeek],
                "Token 指标白名单固定为三个")
    for metric in [MenuBarMetric.tokenToday, .tokenCacheHit, .tokenWeek] {
        assertEqual(MenuBarTokenRefresh.showsTokenMetric([metric]), true,
                    "只启用 " + metric.rawValue + " 也算显示 Token")
    }
    assertEqual(MenuBarTokenRefresh.showsTokenMetric([.downSpeed, .upSpeed, .cpu]), false,
                "只显示网速 / CPU 时不补拉")
    assertEqual(MenuBarTokenRefresh.showsTokenMetric([]), false, "空集合不补拉")
    assertEqual(MenuBarTokenRefresh.showsTokenMetric(Set(MenuBarMetric.allCases)), true,
                "全开时当然要补拉")

    // 2. 首次恒拉：还没有补拉时刻时立刻跑一轮（启动后状态栏第一次就有真数据）
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday], lastPullAt: nil, now: start), true,
                "首次补拉立即放行")

    // 3. 间隔节流：59s 不放行、60s 放行、更久放行
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(59)), false,
                "未满 60s 不补拉")
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(60)), true,
                "满 60s 放行")
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(3600)), true,
                "长时间未拉当然放行")

    // 4. 不显示 Token 时无论多久都不拉（这是「用户没让显示就别偷偷扫」的边界）
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.downSpeed],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(86_400)), false,
                "未显示 Token 指标：一天不拉也不补")

    // 5. 时钟回退按「该拉」处理，不永久卡死
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(-120)), true,
                "时钟回退：按该拉处理")

    // 6. 自定义间隔：非有限 / <=0 回落默认 60s
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(10),
                                              interval: 5), true,
                "自定义 5s 间隔：10s 后放行")
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(10),
                                              interval: 0), false,
                "间隔 0 回落 60s：10s 时仍不放行")
    assertEqual(MenuBarTokenRefresh.needsPull(enabled: [.tokenToday],
                                              lastPullAt: start,
                                              now: start.addingTimeInterval(10),
                                              interval: .infinity), false,
                "间隔非有限回落 60s：10s 时仍不放行")

    // 7. 默认间隔是 60s（写死判据：改它等于改「菜单栏数字多久跟一次」）
    assertEqual(MenuBarTokenRefresh.interval, 60, "默认补拉间隔 60s")

    print("✅ menu bar token refresh works")
}
