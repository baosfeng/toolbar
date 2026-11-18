import Foundation
import NetworkMonitorCore

// MARK: - 开机自启动的展示口径（纯逻辑）

/// 开机自启动开关的显示态与副标题 —— 三个入口共用这一份口径
///
/// 为什么要有它：通用页原来读偏好键、系统权限页读系统登记态，
/// 同一时刻能显示相反结论（用户说的「自启动很多地方都不统一」）。
/// 现在判定只在这里做一次：显示态以系统登记态为准，偏好键只补「待批准」这一档，
/// 视图只负责把 isOn 拨到开关、把 subtitle 写到行上。
///
/// 放 UI 库而不是 App 层：四档文案与开/关是纯规则，TestRunner 能直接断言，
/// 不必构造真实的 SMAppService。
public struct LaunchItemPresentation: Equatable, Sendable {

    /// 开关是否显示为开
    public let isOn: Bool
    /// 行副标题（一句话说清「现在是哪种状态、要不要用户做什么」）
    public let subtitle: String

    /// - Parameters:
    ///   - registration: 系统侧登录项登记态（唯一真相）
    ///   - preferenceEnabled: 偏好键里的用户意图（只影响「待批准」这一档）
    ///   - failureReason: 最近一次注册 / 注销失败的原因（有就写进副标题）
    ///   - appName: 产品显示名
    public init(registration: LaunchAtStartupRegistration,
                preferenceEnabled: Bool,
                failureReason: String? = nil,
                appName: String = AppIdentity.displayName) {
        self.isOn = LaunchAtStartupReconciler.switchState(preferenceEnabled: preferenceEnabled,
                                                          registration: registration)
        self.subtitle = Self.subtitle(registration: registration,
                                      preferenceEnabled: preferenceEnabled,
                                      failureReason: failureReason,
                                      appName: appName)
    }

    /// 副标题：四档登记态各说一句，不把「待批准」混成「已开启」
    static func subtitle(registration: LaunchAtStartupRegistration,
                         preferenceEnabled: Bool,
                         failureReason: String?,
                         appName: String) -> String {
        switch registration {
        case .enabled:
            return "登录后自动启动 \(appName)"
        case .requiresApproval:
            // 残留登记 + 用户已关（含注册失败回滚）时不能说得像已生效
            return preferenceEnabled
                ? "已在系统登录项里登记，等待你在「系统设置 → 登录项」中批准"
                : "系统登录项里有残留登记，当前未启用"
        case .notRegistered, .notFound:
            if let failureReason {
                return "系统未允许开机自启动：\(failureReason)"
            }
            return "当前未登记开机自启动"
        }
    }
}
