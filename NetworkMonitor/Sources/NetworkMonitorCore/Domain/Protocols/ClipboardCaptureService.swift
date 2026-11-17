import Foundation

// MARK: - 采集状态

/// 采集服务状态
public enum ClipboardCaptureState: Equatable, Sendable {
    /// 未启动或已停止
    case stopped
    /// 轮询中
    case running
    /// 用户主动暂停（与 stopped 的区别：暂停是「本来要采但现在不采」，面板要显示可恢复入口）
    case paused
    /// 系统拒绝剪贴板访问（需引导用户去系统设置开启）
    case denied(ClipboardAccessDeniedReason)
}

/// 剪贴板访问被拒的原因
public enum ClipboardAccessDeniedReason: String, Sendable {
    /// NSPasteboard.accessBehavior == .alwaysDeny
    case alwaysDeny
    /// 读取返回空或系统提示拒绝
    case accessDenied
    /// 其他未知原因
    case unknown
}

// MARK: - 采集服务

/// 剪贴板采集服务协议 — 仅协议，实现位于 App 层（PasteboardWatcher）
///
/// 设计约束：
/// - 全流程在主线程（@MainActor）：NSPasteboard 非 Sendable，且 Timer 挂在主 RunLoop common modes
/// - 采集实现内部自行完成「changeCount 未变即返回」「忽略判定」「内容哈希」，
///   产出已可落库的 ClipboardDraft；Core 侧不感知 NSPasteboard
/// - 回调时机：onCapture 在采集成功后、落库前调用，调用方负责入库并发事件通知
@MainActor
public protocol ClipboardCaptureService: AnyObject {

    /// 是否正在采集
    var isRunning: Bool { get }

    /// 用户是否已主动暂停采集（与 `isRunning` 正交：按需模式下不运行时也可以未暂停）
    var isPaused: Bool { get }

    /// 状态变化回调（启动 / 停止 / 权限被拒）
    var onStateChange: ((ClipboardCaptureState) -> Void)? { get set }

    /// 采集成功回调（已通过忽略判定与上限校验；调用方负责落库与发事件通知）
    var onCapture: ((ClipboardDraft) -> Void)? { get set }

    /// 启动轮询（重复调用应幂等）
    func start()

    /// 停止轮询（重复调用应幂等）
    func stop()

    /// 暂停采集：停轮询 + 置暂停偏好（重复调用幂等，不重复打日志）
    ///
    /// 实现约定：暂停期间打开面板也不读剪贴板（暂停语义是「不采」而不是「不轮询」）。
    func pause()

    /// 恢复采集：按当前采集模式重启 + 复位暂停偏好（重复调用幂等）
    func resume()

    /// 在暂停 / 恢复之间切换，返回切换后的暂停态（供面板键位与菜单直接消费）
    @discardableResult
    func togglePause() -> Bool

    /// 立即采集一次（分支 A：面板打开或用户点击「采集当前剪贴板」时调用）
    ///
    /// 与轮询走同一条流水线（含 changeCount 判定、忽略判定与哈希）；无新内容时静默返回。
    func captureNow()
}
