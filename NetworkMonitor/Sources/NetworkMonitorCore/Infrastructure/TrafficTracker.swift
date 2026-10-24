import Foundation

// MARK: - 每日流量追踪

/// 每日流量追踪器 — 管理今日流量累计和每日日志
///
/// 从 MenuBarManager 提取，使用 KeyValueStorage 替代直接 UserDefaults 调用。
/// 职责单一：仅计算和存储每日上下行流量。
public final class TrafficTracker: TrafficTrackingService {
    private let monitor: NetworkMonitoringService
    private let storage: KeyValueStorage

    /// 每日起点（今日开关机/启动时的累计流量基准）
    private var dayStartRx: UInt64 = 0
    private var dayStartTx: UInt64 = 0

    private static let dayStartDateKey = "dayStartDate"
    private static let dayStartRxKey = "dayStartRx"
    private static let dayStartTxKey = "dayStartTx"
    private static let dailyLogKey = "dailyTrafficLog"

    /// 周标签格式化器缓存（`DateFormatter` 初始化昂贵且非线程安全；本类仅主线程使用）
    private let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    /// 日志日期格式化器缓存（本地 `yyyy-MM-dd`）
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 今日流量（下行）
    public var todayRx: UInt64 {
        monitor.totalRx >= dayStartRx ? monitor.totalRx - dayStartRx : 0
    }

    /// 今日流量（上行）
    public var todayTx: UInt64 {
        monitor.totalTx >= dayStartTx ? monitor.totalTx - dayStartTx : 0
    }

    /// 近 7 日每日流量明细（日期降序：今天在最前）
    public var weekEntries: [(label: String, rx: UInt64, tx: UInt64)] {
        var entries: [(label: String, rx: UInt64, tx: UInt64)] = []

        // 今天
        entries.append((label: weekFormatter.string(from: Date()), rx: todayRx, tx: todayTx))

        // 从日志取前 6 天
        let log = storage.array(forKey: Self.dailyLogKey) as? [[String: Any]] ?? []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for entry in log.reversed() {
            guard let dateStr = entry["date"] as? String,
                  let date = dayFormatter.date(from: dateStr),
                  let rx = entry["rx"] as? UInt64,
                  let tx = entry["tx"] as? UInt64 else { continue }
            let daysDiff = cal.dateComponents([.day], from: date, to: today).day ?? 7
            guard daysDiff > 0, daysDiff < 7 else { continue }
            entries.append((label: weekFormatter.string(from: date), rx: rx, tx: tx))
        }

        return entries
    }

    public init(monitor: NetworkMonitoringService, storage: KeyValueStorage = AppContext.shared.storage) {
        self.monitor = monitor
        self.storage = storage
        load()
    }

    /// 解析当日流量基准
    ///
    /// 累计值回退时（崩溃 / 强杀后重启读到更旧的持久化值）以当前累计重建基准：
    /// 否则今日流量会因当前累计小于基准而恒为 0，界面「今日下行/上行」长期显示 0 KB。
    ///
    /// - Parameters:
    ///   - currentRx: 当前累计下行字节
    ///   - currentTx: 当前累计上行字节
    ///   - storedRx: 存储的基准下行字节
    ///   - storedTx: 存储的基准上行字节
    /// - Returns: 应采用的下行 / 上行基准
    public static func resolveBaseline(currentRx: UInt64,
                                       currentTx: UInt64,
                                       storedRx: UInt64,
                                       storedTx: UInt64) -> (rx: UInt64, tx: UInt64) {
        guard currentRx < storedRx || currentTx < storedTx else { return (storedRx, storedTx) }
        return (currentRx, currentTx)
    }

    /// 加载或初始化每日流量起点
    public func load() {
        let storedRx = UInt64(storage.integer(forKey: Self.dayStartRxKey))
        let storedTx = UInt64(storage.integer(forKey: Self.dayStartTxKey))

        // 首次运行：以当前累计值为基准
        guard storedRx != 0 || storedTx != 0 else {
            dayStartRx = monitor.totalRx
            dayStartTx = monitor.totalTx
            persistBaseline()
            return
        }

        let baseline = Self.resolveBaseline(currentRx: monitor.totalRx,
                                            currentTx: monitor.totalTx,
                                            storedRx: storedRx,
                                            storedTx: storedTx)
        dayStartRx = baseline.rx
        dayStartTx = baseline.tx
        guard baseline.rx != storedRx || baseline.tx != storedTx else { return }
        persistBaseline()
    }

    /// 写入基准（日期交由 update() 的日切逻辑维护，避免跨天回退时误吞昨日日志）
    private func persistBaseline() {
        storage.set(Int(dayStartRx), forKey: Self.dayStartRxKey)
        storage.set(Int(dayStartTx), forKey: Self.dayStartTxKey)
    }

    /// 检查日期变更，切换并保存每日日志
    public func update() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let savedDate = storage.object(forKey: Self.dayStartDateKey) as? Date ?? today

        guard !cal.isDate(savedDate, inSameDayAs: today) else { return }

        let yesterdayRx = dayStartRx > 0 && monitor.totalRx >= dayStartRx
            ? monitor.totalRx - dayStartRx : 0
        let yesterdayTx = dayStartTx > 0 && monitor.totalTx >= dayStartTx
            ? monitor.totalTx - dayStartTx : 0

        if yesterdayRx > 0 || yesterdayTx > 0 {
            var log = storage.array(forKey: Self.dailyLogKey) as? [[String: Any]] ?? []
            log.append(["date": dayFormatter.string(from: savedDate), "rx": yesterdayRx, "tx": yesterdayTx])
            if log.count > 30 { log = Array(log.suffix(30)) }
            storage.set(log, forKey: Self.dailyLogKey)
        }

        dayStartRx = monitor.totalRx
        dayStartTx = monitor.totalTx
        storage.set(today, forKey: Self.dayStartDateKey)
        storage.set(Int(dayStartRx), forKey: Self.dayStartRxKey)
        storage.set(Int(dayStartTx), forKey: Self.dayStartTxKey)
    }
}
