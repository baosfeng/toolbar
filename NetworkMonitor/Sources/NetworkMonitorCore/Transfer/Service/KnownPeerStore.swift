import Foundation

// MARK: - 已知设备地址记忆

/// 记住上次成功通信过的设备地址（deviceId → IP）。
///
/// 用途：冷启动时先对**已知地址**单播 `discover`，命中通常几百毫秒；
/// 组播/广播/`/24` 扫描只作为兜底，避免每次都等完整的降级链。
///
/// 地址随 DHCP 变化时无需特殊处理：组播兜底发现新地址后会覆盖旧记录。
public final class KnownPeerStore: @unchecked Sendable {

    private let storage: KeyValueStorage
    private let logger: LoggingService

    /// 存储键（带版本号，便于将来改格式）
    private let storageKey = "transfer.knownPeers.v1"

    /// 保护 cache 与持久化读写的串行队列
    private let queue = DispatchQueue(label: "com.networkmonitor.transfer.knownPeers")

    /// 内存缓存，避免每次探测都反序列化
    private var cache: [String: String]?

    /// 最多记住的设备数，超出后丢弃最早记录（保持有序）
    private let capacity = 32

    public init(storage: KeyValueStorage,
                logger: LoggingService = AppContext.shared.logger) {
        self.storage = storage
        self.logger = logger
    }

    /// 记录设备当前地址；地址未变化时直接返回，不写盘
    public func remember(deviceId: String, ip: String) {
        guard !deviceId.isEmpty, !ip.isEmpty, ip != "0.0.0.0" else { return }
        queue.sync {
            var map = loaded()
            guard map[deviceId] != ip else { return }
            map[deviceId] = ip
            if map.count > capacity {
                // 简单裁剪：保留最近写入的 capacity 条（字典无序，按插入序近似）
                let overflow = map.count - capacity
                for key in map.keys.prefix(overflow) { map.removeValue(forKey: key) }
            }
            persist(map)
            logger.debug("记住设备地址：\(deviceId) → \(ip)")
        }
    }

    /// 已知地址列表（去重）
    public func knownHosts() -> [String] {
        queue.sync { Array(Set(loaded().values)) }
    }

    /// 遗忘某设备（移除配对时调用）
    public func forget(deviceId: String) {
        queue.sync {
            var map = loaded()
            guard map.removeValue(forKey: deviceId) != nil else { return }
            persist(map)
        }
    }

    // MARK: - 内部

    private func loaded() -> [String: String] {
        if let cache { return cache }
        var map: [String: String] = [:]
        if let raw = storage.string(forKey: storageKey),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
        cache = map
        return map
    }

    private func persist(_ map: [String: String]) {
        cache = map
        guard let data = try? JSONEncoder().encode(map),
              let raw = String(data: data, encoding: .utf8) else { return }
        storage.set(raw, forKey: storageKey)
    }
}
