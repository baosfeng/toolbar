import Foundation
import SystemConfiguration

// MARK: - 发现消息

/// UDP 发现消息 — 三种 `type` 字段集一致，`discover` 可只带 `v` / `type`
///
/// 编解码细节（与 Android 端约定一致）：
/// - 版本：`v` 必带且必须落在 `1...currentVersion`，更高版本视为不兼容而忽略
/// - 未知字段：解码时忽略（向前兼容），不因多字段而失败
/// - 缺失可选字段：按空值/默认值补齐，只有 `type` 非法才判为无效消息
/// - 编码时省略空字段，使 `discover` 保持最小报文
public struct DiscoveryMessage: Equatable, Sendable {

    // MARK: 协议常量

    /// 当前协议版本
    public static let currentVersion = 1
    /// 组播地址
    public static let multicastHost = "239.255.77.77"
    /// 发现层 UDP 端口
    public static let udpPort: UInt16 = 53318
    /// 心跳间隔（秒）
    public static let heartbeatInterval: TimeInterval = 5
    /// 启动连发次数
    public static let startupBurstCount = 3
    /// 启动连发间隔（秒）
    public static let startupBurstInterval: TimeInterval = 0.5
    /// 超过该时长未收到公告判定离线（秒）
    public static let offlineAfter: TimeInterval = 15
    /// 超过该时长未收到公告从列表移除（秒）
    public static let removeAfter: TimeInterval = 60
    /// 同一来源 IP 应答 `discover` 的冷却时长（秒）
    public static let offerCooldown: TimeInterval = 2

    // MARK: 消息类型

    /// `announce` 周期公告；`discover` 主动查询；`offer` 对 `discover` 的单播应答
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case announce
        case discover
        case offer
    }

    // MARK: 字段

    /// 协议版本
    public var v: Int
    /// 消息类型
    public var type: Kind
    /// 发送方设备唯一标识
    public var deviceId: String
    /// 设备展示名
    public var alias: String
    /// `mac` / `android`
    public var deviceType: String
    /// 发送方 HTTP 端口
    public var port: Int
    /// 传输协议名，当前固定 `http`
    public var proto: String
    /// 能力：`send` / `recv`
    public var caps: [String]
    /// 应用版本
    public var appVersion: String
    /// 发送时间（Unix 秒）
    public var ts: Int

    // MARK: 初始化

    public init(v: Int = DiscoveryMessage.currentVersion,
                type: Kind,
                deviceId: String = "",
                alias: String = "",
                deviceType: String = "",
                port: Int = 0,
                proto: String = "http",
                caps: [String] = [],
                appVersion: String = "",
                ts: Int = 0) {
        self.v = v
        self.type = type
        self.deviceId = deviceId
        self.alias = alias
        self.deviceType = deviceType
        self.port = port
        self.proto = proto
        self.caps = caps
        self.appVersion = appVersion
        self.ts = ts
    }

    /// 构造主动查询报文（仅 `v` + `type`）
    public static func discover(ts: Date = Date()) -> DiscoveryMessage {
        DiscoveryMessage(type: .discover, ts: Int(ts.timeIntervalSince1970))
    }

    /// 构造公告报文（本机身份 + 端口）
    public static func announce(identity: LocalIdentity, kind: Kind = .announce,
                                now: Date = Date()) -> DiscoveryMessage {
        DiscoveryMessage(type: kind,
                         deviceId: identity.deviceId,
                         alias: identity.alias,
                         deviceType: identity.deviceType,
                         port: identity.port,
                         proto: "http",
                         caps: ["send", "recv"],
                         appVersion: identity.appVersion,
                         ts: Int(now.timeIntervalSince1970))
    }

    // MARK: 版本兼容

    /// 版本是否兼容（1…currentVersion 之外一律不处理）
    public var isSupportedVersion: Bool {
        v >= 1 && v <= Self.currentVersion
    }

    /// 是否为携带完整设备信息、可写入设备表的消息
    public var carriesIdentity: Bool {
        !deviceId.isEmpty && port > 0
    }

    // MARK: 编码

    /// 编码为 JSON（空字段省略；`v` / `type` 始终输出）
    public func encoded() -> Data? {
        var dict: [String: Any] = ["v": v, "type": type.rawValue]
        if !deviceId.isEmpty { dict["deviceId"] = deviceId }
        if !alias.isEmpty { dict["alias"] = alias }
        if !deviceType.isEmpty { dict["deviceType"] = deviceType }
        if port > 0 { dict["port"] = port }
        if !proto.isEmpty, carriesIdentity || proto != "http" { dict["proto"] = proto }
        if !caps.isEmpty { dict["caps"] = caps }
        if !appVersion.isEmpty { dict["appVersion"] = appVersion }
        if ts > 0 { dict["ts"] = ts }
        return try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
    }

    // MARK: 解码

    /// 解码 JSON — 失败返回 nil（不抛异常，发现层不应让脏包打断接收循环）
    public static func decode(_ data: Data) -> DiscoveryMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return nil }

        // `v` 与 `type` 是必带字段：缺失即判无效
        guard let version = intValue(dict["v"]), let kindText = dict["type"] as? String,
              let kind = Kind(rawValue: kindText)
        else { return nil }

        let message = DiscoveryMessage(
            v: version,
            type: kind,
            deviceId: dict["deviceId"] as? String ?? "",
            alias: dict["alias"] as? String ?? "",
            deviceType: dict["deviceType"] as? String ?? "",
            port: intValue(dict["port"]) ?? 0,
            proto: dict["proto"] as? String ?? "http",
            caps: (dict["caps"] as? [String]) ?? [],
            appVersion: dict["appVersion"] as? String ?? "",
            ts: intValue(dict["ts"]) ?? 0
        )
        return message.isSupportedVersion ? message : nil
    }

    /// 数字字段容错读取（JSON 数字一律是 NSNumber；布尔值不参与该字段）
    private static func intValue(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber else { return nil }
        return number.intValue
    }
}

// MARK: - 本机身份

/// 本机在局域网中的身份信息（发现公告与 `/info` 响应共用）
public struct LocalIdentity: Equatable, Sendable {
    public var deviceId: String
    public var alias: String
    public var port: Int
    public var appVersion: String

    /// 设备类型固定为 mac
    public var deviceType: String { "mac" }

    public init(deviceId: String, alias: String, port: Int, appVersion: String) {
        self.deviceId = deviceId
        self.alias = alias
        self.port = port
        self.appVersion = appVersion
    }

    /// 由主机名派生稳定的设备 id（形如 `mac-3b1e`）
    public static func makeDefault(port: Int, appVersion: String) -> LocalIdentity {
        let host = ProcessInfo.processInfo.hostName
        var hash: UInt32 = 2166136261
        for byte in host.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16777619
        }
        let suffix = String(format: "%04x", hash & 0xFFFF)
        return LocalIdentity(deviceId: "mac-\(suffix)",
                             alias: preferredDisplayName(),
                             port: port,
                             appVersion: appVersion)
    }

    /// 对外展示的设备名：优先系统「通用 → 共享 → 电脑名称」里用户设置的名字，
    /// 其次主机名，最后回落「用户名 + 的 Mac」。不使用设备型号或设备号。
    static func preferredDisplayName() -> String {
        if let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            let trimmed = computerName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let host = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty { return host }
        return "\(NSUserName()) 的 Mac"
    }
}
