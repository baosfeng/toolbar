import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 权限状态提供者

/// 设置页与面板读权限状态时依赖的协议 —— 只读快照 + 观测 + 三个显式动作
///
/// 页面不直接调系统 API：读取与请求全部收敛到实现方（`SystemPermissionCenter`），
/// 这样设置页、面板页脚与引导文案不会各算一套口径。
@MainActor
protocol SystemPermissionProviding: AnyObject {

    /// 最新快照（UI 只读它）
    var snapshot: SystemPermissionSnapshot { get }
    /// 应用包绝对路径（引导文案与 Finder 定位共用）
    var appPath: String { get }

    /// 重新读取三类权限（静默，不弹系统框）
    @discardableResult
    func refresh() -> SystemPermissionSnapshot
    /// 请求某一类权限（会登记进系统设置清单并弹一次系统提示，只在用户点击时调用）
    func request(_ kind: SystemPermissionKind)
    /// 在 Finder 中显示应用包
    func revealAppInFinder()

    /// 订阅快照变化（返回的 token 用于退订；视图在 deinit 里退订）
    ///
    /// 为什么是订阅而不是「谁刷新谁通知」：刷新时机有三处（应用激活 / 面板打开 /
    /// 设置页按钮），让视图各自去挂系统通知会漏掉另外两处。
    @discardableResult
    func addObserver(_ handler: @escaping (SystemPermissionSnapshot) -> Void) -> UUID
    /// 退订
    func removeObserver(_ token: UUID)
}
