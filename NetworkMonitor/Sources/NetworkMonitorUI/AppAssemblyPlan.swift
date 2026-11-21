import Foundation

// MARK: - 应用装配声明（唯一真源）

/// 全部装配阶段的声明：**顺序即声明序**，依赖由 `requires` 显式表达
///
/// 改造前这段顺序只存在于 `AppCoordinator.start()` 的代码位置与注释里，
/// 新增模块要记得 `start()` 加一处、`stop()` 再加一处逆序。现在声明放这里
/// （纯值，TestRunner 直接断言），执行体按名字在 App 侧配对。
///
/// 口径：`legacyStartOrder` 是改造前手写顺序的冻结快照，`declarations` 经拓扑排序后
/// 必须与它逐项相同（同层按声明序稳定），否则测试判红。
public enum AppAssemblyPlan {

    // MARK: 阶段名（依赖引用用的稳定名字）

    public static let database = "数据库"
    public static let network = "网络监控"
    public static let traffic = "流量追踪"
    public static let notifications = "通知与音效"
    public static let clipboard = "剪贴板"
    public static let snip = "截图"
    public static let permissions = "系统权限"
    public static let transfer = "局域网互传"
    public static let billing = "额度"
    public static let updateCheck = "更新检查"
    public static let settings = "设置窗口"
    public static let screenActivity = "屏幕活动"
    public static let token = "Token 统计"
    public static let systemMonitor = "系统监控"
    public static let menuBar = "菜单栏"
    public static let trafficPersistence = "定时落盘"
    public static let autoUpdateCheck = "自动更新检查"
    public static let launchCleanup = "启动清理"
    public static let smoothScroll = "鼠标滚轮平滑滚动"

    /// 阶段声明表（顺序 = 改造前手写顺序；`requires` 精确表达现注释里的真实依赖）
    public static let declarations: [AssembleStageSpec] = [
        // 1. 数据库：同一实例同时满足 DatabaseService / ClipboardRepository / ClipboardOCRRepository
        AssembleStageSpec(name: database),
        // 2. 网络监控：读 storage 的 totalRx / totalTx 起步，不依赖任何阶段
        AssembleStageSpec(name: network),
        // 3. 流量追踪：构造时就要拿到网络监控实例
        AssembleStageSpec(name: traffic, requires: [network]),
        // 3b. 通知与音效：剪贴板与额度都从这里取实例（必须早于它们）
        AssembleStageSpec(name: notifications),
        // 4. 剪贴板链路：落库要数据库，音效 / 触觉 / 通知偏好来自通知与音效
        AssembleStageSpec(name: clipboard, requires: [database, notifications]),
        // 4b. 截图 / 贴图：独立链路
        AssembleStageSpec(name: snip),
        // 4c. 系统权限：屏幕录制状态读截图捕获服务的 preflight（必须在截图之后）
        AssembleStageSpec(name: permissions, requires: [snip, notifications]),
        // 5. 局域网互传：面板控制器注入通知服务与音效播放器
        AssembleStageSpec(name: transfer, requires: [notifications]),
        // 6. 额度链路：提醒服务注入通知服务与音效播放器
        AssembleStageSpec(name: billing, requires: [notifications]),
        // 6c. 更新检查：设置页「关于」的数据源
        AssembleStageSpec(name: updateCheck),
        // 6d. 设置窗口：额度页与关于页直接拿上面两阶段的实例
        AssembleStageSpec(name: settings, requires: [billing, updateCheck]),
        // 6e. 屏幕活动：暂停 / 恢复额度后台轮询（弱引用 billingMonitor）
        AssembleStageSpec(name: screenActivity, requires: [billing]),
        // 6f. Token 统计：依赖数据库实例
        AssembleStageSpec(name: token, requires: [database]),
        // 6g. 系统监控：独立采样链路
        AssembleStageSpec(name: systemMonitor),
        // 7. 菜单栏：注入前面装配出的全部服务
        AssembleStageSpec(name: menuBar,
                          requires: [database, network, traffic, clipboard, notifications,
                                     transfer, billing, token, systemMonitor]),
        // 8. 累计流量定期落盘：读网络监控的累计字节
        AssembleStageSpec(name: trafficPersistence, requires: [network]),
        // 8b. 启动 5 秒后自动检查更新
        AssembleStageSpec(name: autoUpdateCheck, requires: [updateCheck]),
        // 9. 启动清理：剪贴板容量清理与孤儿清扫（读数据库与剪贴板偏好）
        AssembleStageSpec(name: launchCleanup, requires: [database, clipboard]),
        // 10. 鼠标滚轮平滑：可选模块，默认关闭；不依赖任何前面的阶段
        //     （只读偏好，关着就什么都不装，不碰全局输入路径）
        AssembleStageSpec(name: smoothScroll),
    ]

    /// 改造前 `AppCoordinator.start()` 的手写执行顺序（冻结快照，不随实现改动）
    public static let legacyStartOrder: [String] = [
        "数据库", "网络监控", "流量追踪", "通知与音效", "剪贴板", "截图", "系统权限",
        "局域网互传", "额度", "更新检查", "设置窗口", "屏幕活动", "Token 统计", "系统监控",
        "菜单栏", "定时落盘", "自动更新检查", "启动清理", "鼠标滚轮平滑滚动",
    ]

    /// 带反向清理的阶段（改造前手写在这个集合上的顺序见 `legacyTeardownOrder`）
    public static let teardownStages: [String] = [
        database, clipboard, transfer, screenActivity, trafficPersistence, smoothScroll,
    ]

    /// 改造前 `stop()` 的清理顺序（冻结快照）——必须等于启动顺序的逆序裁剪
    public static let legacyTeardownOrder: [String] = [
        smoothScroll, trafficPersistence, screenActivity, transfer, clipboard, database,
    ]

    /// 声明表经拓扑排序得到的实际启动顺序
    public static func resolvedStartOrder() -> Result<[String], AssemblePlanError> {
        AssembleTopology.plan(declarations)
    }

    /// 启动顺序的逆序裁剪（只保留带 teardown 的阶段）
    public static func resolvedTeardownOrder(_ startOrder: [String]) -> [String] {
        AssembleTopology.teardownOrder(startOrder).filter { teardownStages.contains($0) }
    }
}
