import Foundation

// MARK: - 传输方向

/// 传输方向：发送（Mac → 对端）/ 接收（对端 → Mac）
public enum TransferDirection: String, Sendable, Codable, CaseIterable {
    case send
    case recv
}

// MARK: - 会话状态

/// 会话状态（迁移规则集中在 `TransferSessionMachine`，此处只定义取值）
///
/// 主链路：`pending → offering → awaitingConfirm → transferring → verifying → completed`；
/// 任一活动状态均可转 `failed` / `cancelled`。
public enum TransferState: String, Sendable, Codable, CaseIterable {
    case pending
    case offering
    case awaitingConfirm
    case transferring
    case verifying
    case completed
    case failed
    case cancelled

    /// 是否已结束（终结态不再接受任何事件）
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    /// 是否处于进行中（UI 用来决定是否展示进度）
    public var isActive: Bool { !isTerminal }
}

// MARK: - 传输文件

/// 单个待传输文件（发送端清单项 / 接收端落盘项共用）
public struct TransferFile: Identifiable, Equatable, Sendable, Codable {
    /// 会话内唯一标识（发送端生成，`f1`…`fN`）
    public let fileId: String
    /// 发送端给出的原始文件名
    public let name: String
    /// 已传输字节数从 0 开始，用于进度展示
    public var transferred: Int64
    /// 实际接收 / 发送偏移（断点续传时从该位置继续）
    public var offset: Int64
    /// 文件总字节数
    public let size: Int64
    /// 发送端计算的 sha256（十六进制小写）
    public let sha256: String
    /// MIME 类型（未知时 `application/octet-stream`）
    public let mime: String

    public var id: String { fileId }

    public init(fileId: String, name: String, size: Int64, sha256: String,
                mime: String = "application/octet-stream",
                offset: Int64 = 0, transferred: Int64 = 0) {
        self.fileId = fileId
        self.name = name
        self.size = size
        self.sha256 = sha256
        self.mime = mime
        self.offset = offset
        self.transferred = transferred
    }

    /// 进度比例（0…1；size 非正时视为 0，避免除零）
    public var fraction: Double {
        guard size > 0 else { return 0 }
        return min(1, max(0, Double(transferred) / Double(size)))
    }
}

// MARK: - 传输会话

/// 一次传输会话 — 一个 `offer` 对应一个会话，含 1…N 个文件
public struct TransferSession: Identifiable, Equatable, Sendable {
    /// 会话标识（接收端生成，hex）
    public let id: String
    public let direction: TransferDirection
    /// 对端设备 id（发送时为目标设备，接收时为来源设备）
    public let peerDeviceId: String
    /// 本会话的鉴权 token（`/offer` 下发，`PUT /upload` 校验）
    public var token: String
    public var files: [TransferFile]
    public var state: TransferState
    public let createdAt: Date
    /// 接收端最终落盘目录（发送端为空）
    public var directory: URL?

    public init(id: String, direction: TransferDirection, peerDeviceId: String, token: String,
                files: [TransferFile], state: TransferState, createdAt: Date,
                directory: URL? = nil) {
        self.id = id
        self.direction = direction
        self.peerDeviceId = peerDeviceId
        self.token = token
        self.files = files
        self.state = state
        self.createdAt = createdAt
        self.directory = directory
    }

    /// 全部文件总字节
    public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    /// 已传输总字节
    public var totalTransferred: Int64 { files.reduce(0) { $0 + $1.transferred } }

    /// 整体进度（0…1）
    public var fraction: Double {
        let total = totalSize
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(totalTransferred) / Double(total)))
    }

    /// 按 fileId 取文件下标
    public func index(ofFile fileId: String) -> Int? {
        files.firstIndex { $0.fileId == fileId }
    }
}

// MARK: - 远程设备

/// 局域网内可见的对端设备（发现层写入，Service 与 UI 读取）
public struct RemoteDevice: Identifiable, Equatable, Sendable, Codable {
    /// 对方自报的设备唯一标识
    public let deviceId: String
    public var alias: String
    /// `mac` / `android`
    public var deviceType: String
    /// 最近一次公告来源 IP
    public var ip: String
    /// 对方 HTTP 端口（公告上报，可能不是 53319）
    public var port: Int
    public var appVersion: String
    public var lastSeenAt: Date
    /// 是否已配对（配对记忆由 Service 维护，写入此字段供 UI 展示）
    public var isPaired: Bool
    /// 是否在线（15s 内收到公告）
    public var isOnline: Bool

    public var id: String { deviceId }

    public init(deviceId: String, alias: String, deviceType: String, ip: String, port: Int,
                appVersion: String, lastSeenAt: Date, isPaired: Bool = false, isOnline: Bool = true) {
        self.deviceId = deviceId
        self.alias = alias
        self.deviceType = deviceType
        self.ip = ip
        self.port = port
        self.appVersion = appVersion
        self.lastSeenAt = lastSeenAt
        self.isPaired = isPaired
        self.isOnline = isOnline
    }

    /// 传输基地址（发现层异常时可直接拼 `/info` 探测）
    public var baseURL: URL? {
        URL(string: "http://\(ip):\(port)/api/v1")
    }
}

// MARK: - 设备存活判定

/// 设备存活状态 — 15s 未收到公告标离线，60s 未收到则移除
public enum DeviceLiveness: Equatable, Sendable {
    case online
    case offline
    case removed

    /// 纯函数判定：便于单测穷举边界
    public static func evaluate(now: Date, lastSeenAt: Date,
                                offlineAfter: TimeInterval = 15,
                                removeAfter: TimeInterval = 60) -> DeviceLiveness {
        let elapsed = now.timeIntervalSince(lastSeenAt)
        if elapsed >= removeAfter { return .removed }
        if elapsed >= offlineAfter { return .offline }
        return .online
    }
}
