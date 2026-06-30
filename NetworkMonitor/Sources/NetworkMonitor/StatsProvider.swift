import Foundation
import SQLite3

/// 今日统计数据结构
struct TodayStats {
    /// 活跃时间（秒）
    let activeSeconds: TimeInterval
    /// 击键总数
    let keyPressCount: Int
    /// 亮屏时间（秒）
    let screenOnSeconds: TimeInterval
    /// 息屏时间（秒）
    let screenOffSeconds: TimeInterval
    /// 应用排行
    let appRanking: [AppUsage]
    /// 最近的 CPU 使用率
    let cpuUsage: Double
    /// 内存使用（MB）
    let memoryUsedMB: Int
    /// 总内存（MB）
    let memoryTotalMB: Int
    /// 网络下载速率（字节/秒）
    let netDownloadSpeed: UInt64
    /// 网络上传速率（字节/秒）
    let netUploadSpeed: UInt64

    static let empty = TodayStats(
        activeSeconds: 0, keyPressCount: 0,
        screenOnSeconds: 0, screenOffSeconds: 0,
        appRanking: [], cpuUsage: 0,
        memoryUsedMB: 0, memoryTotalMB: 0,
        netDownloadSpeed: 0, netUploadSpeed: 0
    )
}

/// 应用使用数据
struct AppUsage: Comparable {
    let name: String
    let bundleID: String
    let duration: TimeInterval // 前台使用秒数

    static func < (lhs: AppUsage, rhs: AppUsage) -> Bool {
        lhs.duration < rhs.duration
    }
}

/// 统计查询器：从 SQLite 中查询今日统计数据
final class StatsProvider {

    private let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    /// 查询今日统计数据
    func fetchTodayStats() -> TodayStats {
        let startOfDay = startOfDayTimestamp()

        return TodayStats(
            activeSeconds: calculateActiveSeconds(from: startOfDay),
            keyPressCount: countKeyPresses(from: startOfDay),
            screenOnSeconds: calculateScreenOnSeconds(from: startOfDay),
            screenOffSeconds: calculateScreenOffSeconds(from: startOfDay),
            appRanking: fetchAppRanking(from: startOfDay),
            cpuUsage: fetchLatestCPUUsage(from: startOfDay),
            memoryUsedMB: fetchLatestMemoryUsed(from: startOfDay) ?? 0,
            memoryTotalMB: Int(ProcessInfo.processInfo.physicalMemory / 1024 / 1024),
            netDownloadSpeed: fetchLatestNetDownload(from: startOfDay),
            netUploadSpeed: fetchLatestNetUpload(from: startOfDay)
        )
    }

    // MARK: - 活跃时间

    /// 计算今日活跃时间：基于应用切换时间差
    private func calculateActiveSeconds(from startOfDay: TimeInterval) -> TimeInterval {
        // 简化实现：统计 app_switch 事件数，估算活跃时间
        let sql = """
            SELECT COUNT(*), MIN(timestamp), MAX(timestamp)
            FROM events
            WHERE event_type = 'app_switch'
              AND timestamp >= \(startOfDay)
            """

        var count: Int32 = 0
        var minTS: TimeInterval = 0
        var maxTS: TimeInterval = 0

        database.query(sql: sql) { stmt in
            count = sqlite3_column_int(stmt, 0)
            minTS = sqlite3_column_double(stmt, 1)
            maxTS = sqlite3_column_double(stmt, 2)
        }

        guard count > 0, maxTS > minTS else { return 0 }
        // 估算：从第一次切换到最后一次切换之间的时间
        return maxTS - minTS
    }

    // MARK: - 击键计数

    private func countKeyPresses(from startOfDay: TimeInterval) -> Int {
        let sql = """
            SELECT COALESCE(SUM(
                CASE WHEN extra_data IS NOT NULL AND extra_data != ''
                THEN CAST(json_extract(extra_data, '$.count') AS INTEGER)
                ELSE 0 END
            ), 0)
            FROM events
            WHERE event_type = 'key_press'
              AND timestamp >= \(startOfDay)
            """

        var total: Int = 0
        database.query(sql: sql) { stmt in
            total = Int(sqlite3_column_int(stmt, 0))
        }
        return total
    }

    // MARK: - 屏幕时间

    private func calculateScreenOnSeconds(from startOfDay: TimeInterval) -> TimeInterval {
        calculateScreenTime(from: startOfDay, onType: "screen_wake", offType: "screen_sleep")
    }

    private func calculateScreenOffSeconds(from startOfDay: TimeInterval) -> TimeInterval {
        calculateScreenTime(from: startOfDay, onType: "screen_sleep", offType: "screen_wake")
    }

    /// 计算屏幕时间：通过 screen_sleep/screen_wake 事件配对
    private func calculateScreenTime(from startOfDay: TimeInterval, onType: String, offType: String) -> TimeInterval {
        let sql = """
            SELECT timestamp FROM events
            WHERE event_type IN ('\(onType)', '\(offType)')
              AND timestamp >= \(startOfDay)
            ORDER BY timestamp ASC
            """

        var timestamps: [TimeInterval] = []
        database.query(sql: sql) { stmt in
            timestamps.append(sqlite3_column_double(stmt, 0))
        }

        var total: TimeInterval = 0
        var i = 0
        while i < timestamps.count {
            let start = timestamps[i]
            // 检查事件类型是否匹配 onType
            let checkSQL = """
                SELECT event_type FROM events
                WHERE timestamp = \(start) AND event_type IN ('\(onType)', '\(offType)')
                LIMIT 1
                """
            var isOnEvent = false
            database.query(sql: checkSQL) { stmt in
                if let cStr = sqlite3_column_text(stmt, 0) {
                    isOnEvent = String(cString: cStr) == onType
                }
            }

            if isOnEvent, i + 1 < timestamps.count {
                total += timestamps[i + 1] - timestamps[i]
                i += 2
            } else {
                i += 1
            }
        }
        return total
    }

    // MARK: - 应用排行

    private func fetchAppRanking(from startOfDay: TimeInterval) -> [AppUsage] {
        let sql = """
            SELECT app_name, app_bundle_id, COUNT(*) as switch_count,
                   MIN(timestamp) as first_seen, MAX(timestamp) as last_seen
            FROM events
            WHERE event_type = 'app_switch'
              AND timestamp >= \(startOfDay)
              AND app_name != ''
            GROUP BY app_bundle_id
            ORDER BY last_seen - first_seen DESC
            LIMIT 8
            """

        var rankings: [(name: String, bundleID: String, duration: TimeInterval)] = []
        database.query(sql: sql) { stmt in
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let bundleID = String(cString: sqlite3_column_text(stmt, 1))
            let firstSeen = sqlite3_column_double(stmt, 3)
            let lastSeen = sqlite3_column_double(stmt, 4)
            let duration = lastSeen - firstSeen
            if duration > 0 {
                rankings.append((name, bundleID, duration))
            }
        }

        return rankings
            .sorted { $0.duration > $1.duration }
            .map { AppUsage(name: $0.name, bundleID: $0.bundleID, duration: $0.duration) }
    }

    // MARK: - 系统数据

    private func fetchLatestCPUUsage(from startOfDay: TimeInterval) -> Double {
        fetchLatestSampleValue(from: startOfDay, key: "cpu") ?? 0
    }

    private func fetchLatestMemoryUsed(from startOfDay: TimeInterval) -> Int? {
        guard let value = fetchLatestSampleValue(from: startOfDay, key: "memory_used_mb") else {
            return nil
        }
        return Int(value)
    }

    private func fetchLatestNetDownload(from startOfDay: TimeInterval) -> UInt64 {
        UInt64(fetchLatestSampleValue(from: startOfDay, key: "net_rx") ?? 0)
    }

    private func fetchLatestNetUpload(from startOfDay: TimeInterval) -> UInt64 {
        UInt64(fetchLatestSampleValue(from: startOfDay, key: "net_tx") ?? 0)
    }

    /// 从最近的 system_sample 事件中提取指定字段的值
    private func fetchLatestSampleValue(from startOfDay: TimeInterval, key: String) -> Double? {
        let sql = """
            SELECT extra_data FROM events
            WHERE event_type = 'system_sample'
              AND timestamp >= \(startOfDay)
              AND extra_data IS NOT NULL
            ORDER BY timestamp DESC
            LIMIT 1
            """

        var result: Double?
        database.query(sql: sql) { stmt in
            if let cStr = sqlite3_column_text(stmt, 0) {
                let json = String(cString: cStr)
                if let data = json.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let value = dict[key] as? NSNumber {
                    result = value.doubleValue
                }
            }
        }
        return result
    }

    // MARK: - 辅助

    private func startOfDayTimestamp() -> TimeInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return startOfDay.timeIntervalSince1970
    }
}
