import AppKit
import NetworkMonitorCore
import NetworkMonitorFeatureSmoothScroll

// MARK: - 应用协调器（鼠标滚轮平滑接线）

/// 鼠标滚轮平滑的装配与热生效
///
/// 这里是唯一会碰全局输入路径的地方：引擎本身不读 `AppContext.shared`，
/// 偏好与日志都从组合根注入。关闭态下引擎不装 tap、不建帧循环，
/// 也就不会对系统滚动产生任何影响。
///
/// 热生效走**注入闭包**而不是 AppEvents：写偏好的只有「通用」页这一张卡，
/// 闭包能让引擎在写完的同一拍重新读参数（同步），卡里的状态行当场就能显示
/// 「已启用 / 缺少辅助功能权限」，不用等下一轮 run loop。
extension AppCoordinator {

    /// 装配：建引擎并按偏好决定是否接管
    func setupScrollSmoothing() {
        let engine = ScrollSmoothingEngine(
            settings: SmoothScrollSettings(storage: AppContext.shared.storage),
            logger: logger)
        scrollSmoothingEngine = engine
        // 首次按偏好启动：关着就是一次幂等的空转，不会装 tap
        engine.reload()
    }

    /// 停止：拆 tap、停帧循环（幂等）
    func teardownScrollSmoothing() {
        scrollSmoothingEngine?.stop()
        scrollSmoothingEngine = nil
    }

    /// 设置页写偏好后调用：引擎同步重新读参数并热生效
    func applyScrollSmoothingPreferences() {
        scrollSmoothingEngine?.reload()
    }

    /// 设置页要的一行状态说明（引擎未装配时按关闭态显示）
    var scrollSmoothingStateText: String {
        (scrollSmoothingEngine?.state ?? .idle).displayText
    }
}
