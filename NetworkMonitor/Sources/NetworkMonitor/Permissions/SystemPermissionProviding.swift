import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 权限状态提供者

/// 设置页与面板读权限状态时依赖的协议 —— 只读快照 + 观测 + 显式动作
///
/// 页面不直接调系统 API、也不自己拼系统设置深链：读取、请求与深链全部收敛到实现方
/// （`SystemPermissionCenter`），这样设置页、就地入口与引导文案不会各算一套口径。
@MainActor
protocol SystemPermissionProviding: AnyObject {

    /// 最新快照（UI 只读它）
    var snapshot: SystemPermissionSnapshot { get }
    /// 应用包绝对路径（引导文案与 Finder 定位共用）
    var appPath: String { get }

    /// 签名身份变化提示（nil = 首启动 / 没变化，页面据此决定要不要显示提示带）
    ///
    /// 为什么挂在权限协议上而不是单独一个服务：提示带要的正是「签名变了 + 哪些权限现在没授权」
    /// 这一对信息，拆成两个来源必然出现「有提示没清单」或反之。
    var signingNotice: SigningIdentityNotice? { get }
    /// 当前包是否证书签名（未读到签名身份时为 nil，调用方按 ad-hoc 口径回退）
    var isCertificateSigned: Bool? { get }

    /// 重新读取五类权限（静默，不弹系统框）
    @discardableResult
    func refresh() -> SystemPermissionSnapshot
    /// 检测中 → 异步回填（通知授权是异步 API，不能阻塞主线程）
    func recheck()
    /// 请求某一类权限（会登记进系统设置清单并弹一次系统提示，只在用户点击时调用）
    func request(_ kind: SystemPermissionKind)
    /// 打开对应的系统设置面板（深链唯一出口）
    func openSettings(for kind: SystemPermissionKind)
    /// 在 Finder 中显示应用包
    func revealAppInFinder()
    /// 重启应用（屏幕录制授权后生效需要）
    func restartApp()
    /// 登录项开关（唯一入口；失败时返回回滚说明，nil = 成功）
    @discardableResult
    func setLoginItemEnabled(_ enabled: Bool) -> String?

    /// 订阅快照变化（返回的 token 用于退订；视图在 deinit 里退订）
    ///
    /// 为什么是订阅而不是「谁刷新谁通知」：刷新时机有三处（应用激活 / 面板打开 /
    /// 设置页按钮），让视图各自去挂系统通知会漏掉另外两处。
    @discardableResult
    func addObserver(_ handler: @escaping (SystemPermissionSnapshot) -> Void) -> UUID
    /// 退订
    func removeObserver(_ token: UUID)
}
