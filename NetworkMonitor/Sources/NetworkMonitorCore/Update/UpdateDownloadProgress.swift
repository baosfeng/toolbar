import Foundation

// MARK: - 下载进度（值类型）

/// 一次下载的瞬时进度 —— 只有数据，不含任何界面文案
///
/// 为什么单独成类型而不是散着传三个 Int64：进度要经过「传输层 → 下载器 → 安装器 →
/// 服务 → 界面」四跳，每跳各传一套参数会出现「这层算速度、那层又算一遍」的分叉；
/// 速度与剩余时间统一在采样侧算好（`UpdateDownloadSpeedometer`），下游只读。
public struct UpdateDownloadProgress: Equatable, Sendable {

    /// 已接收字节
    public let receivedBytes: Int64
    /// 总量（nil = 服务端没给 Content-Length，也拿不到清单里的 byteCount）
    public let totalBytes: Int64?
    /// 瞬时速度（字节/秒，滑动窗口采样；未知为 0）
    public let bytesPerSecond: Double
    /// 预计剩余秒数（nil = 没有分母或速度不可用 —— 不给假数字）
    public let estimatedSecondsRemaining: Double?

    public init(receivedBytes: Int64,
                totalBytes: Int64?,
                bytesPerSecond: Double = 0,
                estimatedSecondsRemaining: Double? = nil) {
        self.receivedBytes = max(0, receivedBytes)
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
        self.bytesPerSecond = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        self.estimatedSecondsRemaining = estimatedSecondsRemaining.flatMap {
            $0.isFinite ? max(0, $0) : nil
        }
    }

    /// 已完成比例 0…1（没有分母为 nil —— 界面走不定态，不画一条假的满格）
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    /// 整数百分比 0…100（同上，没有分母为 nil）
    public var percent: Int? {
        guard let fraction else { return nil }
        return Int((fraction * 100).rounded(.down))
    }

    /// 是否已收满（有分母且已到）
    public var isComplete: Bool {
        guard let totalBytes else { return false }
        return receivedBytes >= totalBytes
    }

    /// 由「已收 / 总量 / 速度」推出剩余秒数 —— 分母缺失或速度不可用时为 nil
    public static func remainingSeconds(received: Int64,
                                        total: Int64?,
                                        bytesPerSecond: Double) -> Double? {
        guard let total, total > received, bytesPerSecond > 0 else { return nil }
        return Double(total - received) / bytesPerSecond
    }
}

// MARK: - 速度采样（滑动窗口）

/// 下载速度采样器 —— 滑动窗口内的平均速度，不是首尾平均
///
/// 为什么不用「首尾平均」：下载中途 CDN 抖一下，首尾平均会把整段速度拖低且再也不反弹，
/// 界面上表现为「速度越下越慢、剩余时间越估越长」。窗口取 1.5 秒是折中：
/// 短于 1 秒时低速包的采样噪声会让速度在 0 与峰值之间跳，长于 2 秒则对停滞不敏感。
public struct UpdateDownloadSpeedometer: Sendable {

    /// 窗口长度（秒）
    public let window: TimeInterval
    /// 采样点（时刻 + 累计字节），按时间升序
    private var samples: [(at: Date, bytes: Int64)] = []

    public init(window: TimeInterval = 1.5) {
        self.window = window
    }

    /// 记一次采样并产出进度
    ///
    /// 只保留窗口内的点：更早的点对「当前速度」没有意义，留着会让窗口无限长。
    /// 窗口内不足两个点（刚起步 / 下载太快）时速度给 0、剩余时间给 nil —— 宁可空着也不给假数字。
    public mutating func record(received: Int64,
                                total: Int64?,
                                at now: Date = Date()) -> UpdateDownloadProgress {
        samples.append((at: now, bytes: received))
        let cutoff = now.addingTimeInterval(-window)
        samples.removeAll { $0.at < cutoff }

        var speed: Double = 0
        if let first = samples.first, samples.count > 1 {
            let elapsed = now.timeIntervalSince(first.at)
            // 50ms 以下的间隔除出来是噪声（同一批数据被回调两次），按「还不够算」处理
            if elapsed > 0.05 {
                speed = Double(max(0, received - first.bytes)) / elapsed
            }
        }
        return UpdateDownloadProgress(
            receivedBytes: received,
            totalBytes: total,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: UpdateDownloadProgress.remainingSeconds(
                received: received, total: total, bytesPerSecond: speed))
    }
}

// MARK: - 上报节流

/// 进度上报节流 —— 距上次上报不足 `interval` 就丢掉这一拍
///
/// 为什么必须有：URLSession 的字节回调按网络包频率到达（几十到几百次/秒），
/// 每一拍都往主线程投一次会让设置窗口在安装期间滚不动（`@MainActor` 投递排队）。
/// 100ms ≈ 10 帧/秒，肉眼连续、又不至于把主线程塞满。
public enum UpdateProgressThrottle {

    /// 默认最小间隔（秒）
    public static let defaultInterval: TimeInterval = 0.1

    /// 本次是否该上报（纯函数：调用方自己持有上次上报时刻）
    ///
    /// - 首次恒上报（还没有上次时刻）；
    /// - 时钟回退（本次早于上次）按上报处理：系统时间被改回后差值恒为负，照常拒绝会把进度永久冻住；
    /// - `interval <= 0` 视为不节流。
    public static func shouldEmit(last: Date?,
                                  now: Date,
                                  interval: TimeInterval = defaultInterval) -> Bool {
        guard interval > 0 else { return true }
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        guard elapsed >= 0 else { return true }
        return elapsed >= interval
    }
}

// MARK: - 并发安全的发送侧容器

/// 进度闸门的引用封装 —— 给「@Sendable 闭包要就地节流」用
///
/// 为什么需要引用类型：字节回调是 `@Sendable` 闭包，Swift 6 不允许它修改外部捕获的 var，
/// 而节流必须记住「上次何时上报」。内部加锁即可，判据仍是纯函数 `UpdateProgressThrottle`。
public final class UpdateProgressGate: @unchecked Sendable {

    private let lock = NSLock()
    private var lastEmitted: Date?
    private let interval: TimeInterval

    public init(interval: TimeInterval = UpdateProgressThrottle.defaultInterval) {
        self.interval = interval
    }

    /// 本次是否放行（放行时记下时刻）
    public func shouldEmit(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard UpdateProgressThrottle.shouldEmit(last: lastEmitted, now: now, interval: interval) else {
            return false
        }
        lastEmitted = now
        return true
    }

    /// 重置（每次安装开始前调一次，避免上一轮的时间戳压住新一轮的第一拍）
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        lastEmitted = nil
    }
}

/// 速度采样器的引用封装 —— 同上：`@Sendable` 闭包不能改外部 var
public final class UpdateDownloadMeter: @unchecked Sendable {

    private let lock = NSLock()
    private var speedometer: UpdateDownloadSpeedometer

    public init(window: TimeInterval = 1.5) {
        speedometer = UpdateDownloadSpeedometer(window: window)
    }

    /// 记一次采样并产出进度（线程安全）
    public func record(received: Int64, total: Int64?, at now: Date = Date()) -> UpdateDownloadProgress {
        lock.lock()
        defer { lock.unlock() }
        return speedometer.record(received: received, total: total, at: now)
    }
}
