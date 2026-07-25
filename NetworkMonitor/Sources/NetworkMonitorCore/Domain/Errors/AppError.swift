import Foundation

// MARK: - 应用错误

/// 应用统一错误类型 — 所有领域层错误使用此枚举
public enum AppError: Error, Sendable, LocalizedError {
    // MARK: 数据库错误
    case databaseNotReady
    case databaseOpenFailed(status: Int32)
    case databaseQueryFailed(reason: String)
    case databaseWriteFailed(reason: String)

    // MARK: 网络监控错误
    case networkPollFailed(reason: String)
    case nettopExecutionFailed

    // MARK: Hook 事件错误
    case hookSocketCreateFailed(reason: String)
    case hookSocketBindFailed(reason: String)
    case hookSocketPathTooLong

    // MARK: 系统监控错误
    case cpuSampleFailed
    case memorySampleFailed

    // MARK: 击键监控错误
    case keyMonitorPermissionDenied
    case keyMonitorCreationFailed

    // MARK: 开机自启错误
    case launchAtStartupFailed(reason: String)

    // MARK: 通用
    case unknown(reason: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .databaseNotReady:                 return "数据库未就绪"
        case .databaseOpenFailed(let status):    return "数据库打开失败 (status=\(status))"
        case .databaseQueryFailed(let reason):   return "数据库查询失败: \(reason)"
        case .databaseWriteFailed(let reason):   return "数据库写入失败: \(reason)"
        case .networkPollFailed(let reason):     return "网络轮询失败: \(reason)"
        case .nettopExecutionFailed:             return "nettop 执行失败"
        case .hookSocketCreateFailed(let r):     return "Hook socket 创建失败: \(r)"
        case .hookSocketBindFailed(let r):       return "Hook socket bind 失败: \(r)"
        case .hookSocketPathTooLong:             return "Hook socket 路径过长"
        case .cpuSampleFailed:                   return "CPU 采样失败"
        case .memorySampleFailed:                return "内存采样失败"
        case .keyMonitorPermissionDenied:        return "击键监听权限不足"
        case .keyMonitorCreationFailed:          return "无法创建全局事件监听器"
        case .launchAtStartupFailed(let r):      return "开机自启设置失败: \(r)"
        case .unknown(let r):                    return "未知错误: \(r)"
        }
    }
}
