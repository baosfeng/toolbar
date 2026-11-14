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
        public static let receiveDirectoryPath = "transfer.receiveDirectoryPath"
    }

    /// 免配对窗口可选时长（分钟）
    public static let windowOptions = [5, 10, 30]

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

    // MARK: - 接收目录

    /// 自定义接收目录的绝对路径（nil 表示使用默认目录）
    public var receiveDirectoryPath: String? {
        get {
            guard let stored = storage.string(forKey: Key.receiveDirectoryPath) else { return nil }
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        set {
            guard let path = newValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty else {
                storage.removeObject(forKey: Key.receiveDirectoryPath)
                return
            }
            storage.set(path, forKey: Key.receiveDirectoryPath)
        }
    }

    /// 解析实际使用的接收目录：自定义优先，否则回落到传入的默认目录
    ///
    /// 只影响之后的接收；切换目录不迁移既有文件。
    public func resolvedReceiveDirectory(fallback: URL) -> URL {
        guard let path = receiveDirectoryPath else { return fallback }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - 提示音

    /// 旧「transfer.sound.*」五把键是否还在（迁移提示用；声音已统一到 NotificationPreferences）
    ///
    /// 只读不写：旧键留着不删，用户回退旧版本时设置仍在；新版本只读它们给一次性迁移提示。
    public func legacySoundKeysPresent() -> Bool {
        ["transfer.sound.receive", "transfer.sound.send", "transfer.sound.failure",
         "transfer.sound.deviceAppeared", "transfer.sound.pairingCode"]
            .contains { storage.object(forKey: $0) != nil }
    }
}
