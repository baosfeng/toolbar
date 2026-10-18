import Foundation

// MARK: - 传输域异常

/// 传输域异常 — 发现 / 协议 / 传输 / 会话四层共用，`code` 与协议错误码一一对应
///
/// 规范：不抛裸 `Error` 或字符串；每个 case 自带中文描述，便于日志与界面提示。
public enum TransferError: Error, Equatable, Sendable {
    /// 发现层 socket 创建失败
    case discoverySocket(errno: Int32)
    /// 发现层端口绑定失败（端口被占用或本地网络权限被拒）
    case discoveryBind(errno: Int32)
    /// HTTP 服务端口无法监听（53319…53328 全部被占用）
    case listenerUnavailable(String)
    /// 请求行 / 头部 / 查询参数非法
    case invalidRequest(String)
    /// 路由不存在
    case routeNotFound(String)
    /// 请求体 JSON 非法或字段缺失
    case malformedBody(String)
    /// token 缺失或不匹配
    case tokenMismatch
    /// 会话不存在或已过期
    case sessionNotFound
    /// offset 与已收字节不匹配
    case offsetMismatch(expected: Int64, received: Int64)
    /// 接收端磁盘空间不足
    case diskFull(required: Int64, available: Int64)
    /// 上传体积超过上限（扫码接收单文件 2 GiB，HTTP 413）
    case payloadTooLarge(limit: Int64)
    /// sha256 校验失败
    case checksumMismatch(expected: String, actual: String)
    /// 用户拒绝
    case denied
    /// 确认超时
    case confirmTimeout
    /// 会话状态迁移非法（状态机拒绝）
    case illegalTransition(from: TransferState, to: TransferState)
    /// 对端返回的业务错误（透传 code 与 message）
    case remote(code: Int, message: String)
    /// 读写磁盘失败
    case ioFailed(String)

    /// 协议错误码（0 表示成功，其余见设计文档 3.4）
    public var code: Int {
        switch self {
        case .tokenMismatch: return 4001
        case .sessionNotFound: return 4002
        case .offsetMismatch: return 4003
        case .diskFull: return 4004
        case .payloadTooLarge: return 4008
        case .checksumMismatch: return 4005
        case .denied: return 4006
        case .confirmTimeout: return 4007
        case .remote(let code, _): return code
        default: return 4000
        }
    }

    /// 面向用户 / 日志的中文描述
    public var message: String {
        switch self {
        case .discoverySocket(let errno): return "发现层 socket 创建失败（errno \(errno)）"
        case .discoveryBind(let errno):
            return "发现层 UDP 53318 绑定失败（errno \(errno)），请检查本地网络权限或端口占用"
        case .listenerUnavailable(let detail): return "传输端口监听失败：\(detail)"
        case .invalidRequest(let detail): return "请求非法：\(detail)"
        case .routeNotFound(let path): return "路由不存在：\(path)"
        case .malformedBody(let detail): return "请求体非法：\(detail)"
        case .tokenMismatch: return "token 缺失或不匹配"
        case .sessionNotFound: return "会话不存在或已过期"
        case .offsetMismatch(let expected, let received):
            return "offset 与已收字节不匹配（期望 \(expected)，收到 \(received)）"
        case .diskFull(let required, let available):
            return "磁盘空间不足：需要 \(formatBytesFull(UInt64(max(0, required))))，可用 \(formatBytesFull(UInt64(max(0, available))))"
        case .payloadTooLarge(let limit):
            return "文件超过单文件上限（\(formatBytesFull(UInt64(max(0, limit))))）"
        case .checksumMismatch(let expected, let actual):
            return "sha256 校验失败（期望 \(expected)，实际 \(actual)）"
        case .denied: return "用户拒绝接收"
        case .confirmTimeout: return "确认超时"
        case .illegalTransition(let from, let to):
            return "非法状态迁移：\(from.rawValue) → \(to.rawValue)"
        case .remote(_, let message): return message
        case .ioFailed(let detail): return "读写失败：\(detail)"
        }
    }
}
