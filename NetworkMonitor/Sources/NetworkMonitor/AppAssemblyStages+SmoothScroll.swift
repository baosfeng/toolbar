import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 装配阶段（输入体验：鼠标滚轮平滑）

/// 装配阶段执行体（输入体验）—— 从 `AppAssemblyStages+Features.swift` 拆出
///
/// 拆文件只为守住单文件门禁（≤500 行 / 15 KiB）；阶段本身仍是一处声明、
/// 一处执行体，顺序同样由 `AppAssemblyPlan` 的 requires 拓扑排序决定。
extension AppCoordinator {

    /// 10. 鼠标滚轮平滑（可选模块，默认关闭）
    ///
    /// 唯一会碰全局输入路径的阶段：偏好关着就什么都不装。启动顺序排在最后——
    /// 它与任何阶段都没有依赖，放在末尾既不改变既有顺序，也让「装配失败就停」的
    /// 影响面最小（前面全部就绪之后才装 tap）。
    var smoothScrollStage: AssembleStage {
        AssembleStage(name: AppAssemblyPlan.smoothScroll,
                      run: { env in env.coordinator.setupScrollSmoothing() },
                      teardown: { env in env.coordinator.teardownScrollSmoothing() })
    }
}
