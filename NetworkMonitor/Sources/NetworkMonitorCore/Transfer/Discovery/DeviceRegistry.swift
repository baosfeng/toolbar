import Foundation

// MARK: - 设备表

/// 局域网设备表 — 发现层写入、Service / UI 读取
///
/// 线程模型：内部 `NSLock` 保护状态，任意队列可读写；
/// 状态变化通过 `onChange` 投递到 `callbackQueue`（默认主队列），避免 UI 再自行跳线程。
public final class DeviceRegistry: @unchecked Sendable {

    private let lock = NSLock()
    private var devices: [String: RemoteDevice] = [:]
    private let callbackQueue: DispatchQueue

    /// 设备表变化回调（已排序快照；仅在可见字段变化时触发）
    public var onChange: (@Sendable ([RemoteDevice]) -> Void)?

    public init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    // MARK: - 写入

    /// 用发现消息更新设备表；`discover` 类或缺少身份字段的消息直接忽略
    ///
    /// - Returns: 写入后的设备（无效消息返回 nil）
    @discardableResult
    public func upsert(message: DiscoveryMessage, ip: String, now: Date = Date()) -> RemoteDevice? {
        guard message.carriesIdentity, !ip.isEmpty else { return nil }

        lock.lock()
        let previous = devices[message.deviceId]
        var device = previous ?? RemoteDevice(deviceId: message.deviceId,
                                             alias: message.alias,
                                             deviceType: message.deviceType,
                                             ip: ip,
                                             port: message.port,
                                             appVersion: message.appVersion,
                                             lastSeenAt: now,
                                             isPaired: false,
                                             isOnline: true)
        device.alias = message.alias.isEmpty ? device.alias : message.alias
        device.deviceType = message.deviceType.isEmpty ? device.deviceType : message.deviceType
        device.ip = ip
        device.port = message.port
        device.appVersion = message.appVersion
        device.lastSeenAt = now
        device.isOnline = true
        let visibleFieldsChanged = previous == nil || Self.hasVisibleChange(previous!, device)
        devices[message.deviceId] = device
        let snapshot = Self.sorted(Array(devices.values))
        lock.unlock()

        if visibleFieldsChanged { notify(snapshot) }
        return device
    }

    /// 更新配对标记（配对记忆由 Service 维护）
    public func setPaired(_ paired: Bool, deviceId: String) {
        lock.lock()
        guard var device = devices[deviceId], device.isPaired != paired else {
            lock.unlock()
            return
        }
        device.isPaired = paired
        devices[deviceId] = device
        let snapshot = Self.sorted(Array(devices.values))
        lock.unlock()
        notify(snapshot)
    }

    /// 移除指定设备（用户手动清空列表时使用）
    public func remove(deviceId: String) {
        lock.lock()
        guard devices.removeValue(forKey: deviceId) != nil else {
            lock.unlock()
            return
        }
        let snapshot = Self.sorted(Array(devices.values))
        lock.unlock()
        notify(snapshot)
    }

    // MARK: - 存活判定

    /// 按当前时间推进存活状态：15s→离线、60s→移除
    ///
    /// - Returns: 是否有可见变化（调用方据此决定是否刷新 UI）
    @discardableResult
    public func applyLiveness(now: Date = Date()) -> Bool {
        lock.lock()
        var changed = false
        var removals: [String] = []
        for (deviceId, device) in devices {
            switch DeviceLiveness.evaluate(now: now, lastSeenAt: device.lastSeenAt) {
            case .online:
                continue
            case .offline:
                if device.isOnline {
                    var updated = device
                    updated.isOnline = false
                    devices[deviceId] = updated
                    changed = true
                }
            case .removed:
                removals.append(deviceId)
            }
        }
        for deviceId in removals {
            devices.removeValue(forKey: deviceId)
            changed = true
        }
        let snapshot = Self.sorted(Array(devices.values))
        lock.unlock()

        if changed { notify(snapshot) }
        return changed
    }

    // MARK: - 读取

    /// 当前设备列表快照（在线优先，同级按名称排序）
    public func snapshot() -> [RemoteDevice] {
        lock.lock()
        defer { lock.unlock() }
        return Self.sorted(Array(devices.values))
    }

    /// 取单个设备
    public func device(deviceId: String) -> RemoteDevice? {
        lock.lock()
        defer { lock.unlock() }
        return devices[deviceId]
    }

    /// 已知设备数量
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return devices.count
    }

    // MARK: - 内部

    /// 只比较「可见字段」：`lastSeenAt` 每次心跳都变，不应触发 UI 刷新
    private static func hasVisibleChange(_ lhs: RemoteDevice, _ rhs: RemoteDevice) -> Bool {
        lhs.alias != rhs.alias
            || lhs.deviceType != rhs.deviceType
            || lhs.ip != rhs.ip
            || lhs.port != rhs.port
            || lhs.appVersion != rhs.appVersion
            || lhs.isPaired != rhs.isPaired
            || lhs.isOnline != rhs.isOnline
    }

    /// 在线优先，其次按名称本地化排序
    private static func sorted(_ devices: [RemoteDevice]) -> [RemoteDevice] {
        devices.sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline { return lhs.isOnline }
            return lhs.alias.localizedStandardCompare(rhs.alias) == .orderedAscending
        }
    }

    /// 异步投递变化（不阻塞发现层接收循环）
    private func notify(_ snapshot: [RemoteDevice]) {
        guard let onChange else { return }
        callbackQueue.async { onChange(snapshot) }
    }
}
