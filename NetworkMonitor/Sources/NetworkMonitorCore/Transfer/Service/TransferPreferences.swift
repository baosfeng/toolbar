import Foundation

// MARK: - 传输设置

/// 传输设置 — 收敛全部 `transfer.*` 键名，包装 `KeyValueStorage` 便于测试注入
///
/// 只做键值读写与纯计算，不做 UI；策略判断由 `AcceptancePolicy` 负责。
public final class TransferPreferences: @unchecked Sendable {

    // MARK: 键

    /// 存储键（设置窗与测试共用同一份定义）
    public enum Key {
        public static let autoAcceptEnabled = "transfer.autoAccept.enabled"
        public static let autoAcceptMinutes = "transfer.autoAccept.minutes"
        public static let autoAcceptWindowStart = "transfer.autoAccept.windowStart"
        public static let sizeThresholdMB = "transfer.autoAccept.sizeThresholdMB"
        public static let soundReceive = "transfer.sound.receive"
        public static let soundSend = "transfer.sound.send"
        public static let soundFailure = "transfer.sound.failure"
        public static let soundDeviceAppeared = "transfer.sound.deviceAppeared"
        public static let soundPairingCode = "transfer.sound.pairingCode"
    }

    /// 免配对窗口可选时长（分钟）
    public static let windowOptions = [5, 10, 30]

    /// 提示音事件
    public enum SoundEvent: String, CaseIterable, Sendable {
        case receive
        case send
        case failure
        case deviceAppeared
        case pairingCode

        /// 默认值：完成类默认开，其余默认关（设计文档 §7.3）
        public var defaultEnabled: Bool {
            switch self {
            case .receive, .send: return true
            case .failure, .deviceAppeared, .pairingCode: return false
            }
        }

        /// 设置窗标签
        public var label: String {
            switch self {
            case .receive: return "接收完成"
            case .send: return "发送完成"
            case .failure: return "传输失败"
            case .deviceAppeared: return "新设备出现"
            case .pairingCode: return "配对码生成"
            }
        }

        /// 存储键
        public var key: String {
            switch self {
            case .receive: return Key.soundReceive
            case .send: return Key.soundSend
            case .failure: return Key.soundFailure
            case .deviceAppeared: return Key.soundDeviceAppeared
            case .pairingCode: return Key.soundPairingCode
            }
        }
    }

    // MARK: 依赖

    private let storage: any KeyValueStorage
    private let lock = NSLock()

    public init(storage: any KeyValueStorage = AppContext.shared.storage) {
        self.storage = storage
    }

    // MARK: - 免配对窗口

    /// 开关（开启后才可能进入窗口期）
    public var autoAcceptEnabled: Bool {
        get { storage.bool(forKey: Key.autoAcceptEnabled) }
        set { storage.set(newValue, forKey: Key.autoAcceptEnabled) }
    }

    /// 窗口时长（分钟），非选项值收敛到默认 10 分钟
    public var autoAcceptMinutes: Int {
        get {
            let stored = storage.integer(forKey: Key.autoAcceptMinutes)
            return Self.windowOptions.contains(stored) ? stored : 10
        }
        set {
            let value = Self.windowOptions.contains(newValue) ? newValue : 10
            storage.set(value, forKey: Key.autoAcceptMinutes)
        }
    }

    /// 窗口开始时间（nil 表示未开启窗口）
    public var windowStart: Date? {
        let seconds = storage.double(forKey: Key.autoAcceptWindowStart)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// 窗口结束时间
    public func windowEnd() -> Date? {
        guard let start = windowStart else { return nil }
        return start.addingTimeInterval(Double(autoAcceptMinutes) * 60)
    }

    /// 开始一个免配对窗口（以当前时间为起点）
    public func startWindow(now: Date = Date()) {
        storage.set(now.timeIntervalSince1970, forKey: Key.autoAcceptWindowStart)
    }

    /// 主动结束窗口（开关保持开启，但窗口不再生效）
    public func stopWindow() {
        storage.removeObject(forKey: Key.autoAcceptWindowStart)
    }

    /// 窗口是否仍在生效
    public func isWindowActive(now: Date = Date()) -> Bool {
        guard autoAcceptEnabled, let end = windowEnd() else { return false }
        return now < end
    }

    /// 窗口剩余秒数（未生效时为 0）
    public func windowRemaining(now: Date = Date()) -> TimeInterval {
        guard autoAcceptEnabled, let end = windowEnd() else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// 剩余时间文案：`08:32`；未生效时为空串
    public func windowRemainingText(now: Date = Date()) -> String {
        let remaining = windowRemaining(now: now)
        guard remaining > 0 else { return "" }
        let seconds = Int(remaining.rounded(.down))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - 体积阈值

    /// 免配对码的体积阈值（MB）；0 表示关闭
    public var sizeThresholdMB: Int {
        get { max(0, storage.integer(forKey: Key.sizeThresholdMB)) }
        set { storage.set(max(0, newValue), forKey: Key.sizeThresholdMB) }
    }

    /// 本次 offer 是否落在阈值内（阈值 0 永远不命中）
    public func allowsSize(_ totalBytes: Int64) -> Bool {
        let threshold = sizeThresholdMB
        guard threshold > 0 else { return false }
        return totalBytes <= Int64(threshold) * 1024 * 1024
    }

    /// 阈值是否开启
    public var sizeThresholdEnabled: Bool { sizeThresholdMB > 0 }

    // MARK: - 提示音

    /// 某事件提示音是否开启（未设置时取默认值）
    public func soundEnabled(_ event: SoundEvent) -> Bool {
        guard storage.object(forKey: event.key) != nil else { return event.defaultEnabled }
        return storage.bool(forKey: event.key)
    }

    /// 设置某事件提示音
    public func setSoundEnabled(_ enabled: Bool, for event: SoundEvent) {
        storage.set(enabled, forKey: event.key)
    }
}
