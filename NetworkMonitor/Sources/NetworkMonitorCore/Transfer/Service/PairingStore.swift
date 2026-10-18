import Foundation

// MARK: - 配对记忆

/// 配对记忆 — 按 `deviceId` 保存 `pairingKey`，可持久化、可移除
///
/// 存储走注入的 `KeyValueStorage`（规范禁止直读 `UserDefaults.standard`），
/// 落库形态为 JSON 字符串 `{"and-7f3a9c":"<64 hex>"}`。
public final class PairingStore: @unchecked Sendable {

    /// 存储键
    public static let storageKey = "transfer.pairingKeys"
    /// `pairingKey` 字节数（32 字节 → 64 位 hex）
    public static let keyBytes = 32
    /// PIN 位数
    public static let pinDigits = 4

    private let storage: any KeyValueStorage
    private let lock = NSLock()

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: - 读写

    /// 取某设备的配对 key
    public func key(for deviceId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()[deviceId]
    }

    /// 是否已配对
    public func isPaired(_ deviceId: String) -> Bool {
        key(for: deviceId) != nil
    }

    /// 保存配对 key（覆盖旧值）
    public func save(key: String, for deviceId: String) {
        guard !deviceId.isEmpty, !key.isEmpty else { return }
        lock.lock()
        var map = loadLocked()
        map[deviceId] = key
        persistLocked(map)
        lock.unlock()
    }

    /// 移除配对（移除后回到 PIN 流程）
    public func remove(deviceId: String) {
        lock.lock()
        var map = loadLocked()
        guard map.removeValue(forKey: deviceId) != nil else {
            lock.unlock()
            return
        }
        persistLocked(map)
        lock.unlock()
    }

    /// 已配对设备 id 列表
    public func pairedDeviceIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadLocked().keys).sorted()
    }

    // MARK: - 生成

    /// 生成 `pairingKey`：32 字节随机数 → 64 位小写 hex
    public static func generateKey() -> String {
        var bytes = [UInt8](repeating: 0, count: keyBytes)
        for index in 0..<keyBytes {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// 生成 4 位 PIN（允许前导 0）
    public static func generatePIN() -> String {
        String(format: "%0\(pinDigits)d", Int.random(in: 0...9_999))
    }

    /// 校验 PIN 格式（4 位数字）
    public static func isValidPIN(_ pin: String) -> Bool {
        pin.count == pinDigits && pin.allSatisfy { $0.isNumber }
    }

    // MARK: - 内部

    /// 从存储反序列化（调用方须持锁；不缓存，保证多实例读到同一份数据）
    private func loadLocked() -> [String: String] {
        guard let raw = storage.string(forKey: Self.storageKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// 写回存储（调用方须持锁）
    private func persistLocked(_ map: [String: String]) {
        guard let data = try? JSONEncoder().encode(map),
              let text = String(data: data, encoding: .utf8) else { return }
        storage.set(text, forKey: Self.storageKey)
    }
}
