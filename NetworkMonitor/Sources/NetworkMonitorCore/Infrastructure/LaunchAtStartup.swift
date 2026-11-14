import Foundation

// MARK: - 开机自启动：系统登记状态与启动自愈

/// 系统侧登录项登记状态
///
/// Core 不依赖 ServiceManagement：App 层把 `SMAppService.mainApp.status` 翻译成这四档，
/// 判定与回滚留在这里，测试可以注入假登记器。
public enum LaunchAtStartupRegistration: Equatable, Sendable {
    /// 已登记，开机就会启动
    case enabled
    /// 已登记，但等用户在「系统设置 → 通用 → 登录项」里批准
    case requiresApproval
    /// 从未登记（用户关过，或系统把它移除了）
    case notRegistered
    /// 系统侧找不到登记项：换过 .app 路径、旧包被删后的残留注册就是这一档
    case notFound

    /// 中文文案（日志用）
    public var title: String {
        switch self {
        case .enabled: return "已登记"
        case .requiresApproval: return "等待用户批准"
        case .notRegistered: return "未登记"
        case .notFound: return "系统未找到登记项"
        }
    }
}

/// 登录项登记器 — 把 ServiceManagement 挡在 Core 之外，测试注入假实现
public protocol LaunchAtStartupRegistering: AnyObject, Sendable {
    /// 系统侧当前登记状态
    var registration: LaunchAtStartupRegistration { get }
    func register() throws
    func unregister() throws
}

/// 启动自愈的判定结果
public enum LaunchAtStartupReconcileDecision: Equatable, Sendable {
    /// 不动：偏好为关，或系统侧已就绪
    case skip
    /// 偏好为开但系统侧失效：重新登记
    case register
}

/// 启动自愈的实际结果
public enum LaunchAtStartupReconcileOutcome: Equatable, Sendable {
    /// 无需动作
    case skipped
    /// 已重新登记
    case registered
    /// 重新登记失败，偏好已回滚为关
    case rolledBack(reason: String)
}

// MARK: - 对账器

/// 开机自启动登记对账 —— 用户意图（偏好键）与系统登记状态的唯一交叉点
///
/// 存在理由：`.app` 包名从 NetworkMonitor 改成中文「一览」后，SMAppService 的旧登记仍指向旧包路径，
/// 系统侧状态变成 `.notRegistered` / `.notFound`，而偏好键还是 `true`——设置页显示「已开启」，
/// 实际开机不启动。启动时对账一次即可自愈：偏好为开但系统侧没登记就重新登记，登记失败把偏好回滚为关。
public final class LaunchAtStartupReconciler {

    /// 纯判定：只在「用户要开」且「系统侧没登记」时才重新登记
    ///
    /// `.requiresApproval` 不重新登记也不回滚：登记项还在，缺的是用户去系统设置点一下；
    /// 此时把偏好回滚成关，等于把用户刚表达过的意图擦掉，还会让开关自己弹回关闭。
    public static func decision(preferenceEnabled: Bool,
                                registration: LaunchAtStartupRegistration) -> LaunchAtStartupReconcileDecision {
        guard preferenceEnabled else { return .skip }
        switch registration {
        case .enabled, .requiresApproval: return .skip
        case .notRegistered, .notFound: return .register
        }
    }

    private let storage: any KeyValueStorage
    private let key: String
    private let registrar: any LaunchAtStartupRegistering
    private let logger: LoggingService

    /// - Parameters:
    ///   - storage: 偏好存储（App 注入 AppContext.shared.storage，测试注入隔离 suite）
    ///   - key: 偏好键（App 侧传 ClipboardPreferences.launchAtStartupKey，Core 不认具体业务键名）
    ///   - registrar: 系统登记器（App 侧 SMAppService，测试注入假实现）
    ///   - logger: 日志
    public init(storage: any KeyValueStorage,
                key: String,
                registrar: any LaunchAtStartupRegistering,
                logger: LoggingService) {
        self.storage = storage
        self.key = key
        self.registrar = registrar
        self.logger = logger
    }

    /// 用户意图（偏好键记录，不代表系统侧真的已登记）
    public var isEnabled: Bool {
        storage.bool(forKey: key)
    }

    /// 切换登记状态
    ///
    /// - Parameter enabled: 目标状态
    /// - Returns: 是否成功（失败时已回滚偏好键）
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        storage.set(enabled, forKey: key)
        do {
            if enabled {
                try registrar.register()
            } else {
                try registrar.unregister()
            }
            return true
        } catch {
            logger.error("开机自启动切换失败：\(error.localizedDescription)")
            storage.set(!enabled, forKey: key)
            return false
        }
    }

    /// 启动自愈：把偏好与系统登记状态对一次账
    ///
    /// 只在偏好为开、系统侧又没登记时动作；其余情况什么都不做（含偏好为关——
    /// 启动阶段不替用户注销任何登记）。
    @discardableResult
    public func reconcileAtLaunch() -> LaunchAtStartupReconcileOutcome {
        let preferenceEnabled = isEnabled
        let registration = registrar.registration
        switch Self.decision(preferenceEnabled: preferenceEnabled, registration: registration) {
        case .skip:
            if preferenceEnabled, registration == .requiresApproval {
                logger.warning("开机自启动等待用户在系统设置里批准，偏好保持为开")
            }
            return .skipped
        case .register:
            do {
                try registrar.register()
                logger.info("开机自启动已按偏好重新登记（原系统状态：\(registration.title)）")
                return .registered
            } catch {
                let reason = error.localizedDescription
                storage.set(false, forKey: key)
                logger.error("开机自启动重新登记失败，偏好已回滚为关：\(reason)")
                return .rolledBack(reason: reason)
            }
        }
    }
}
