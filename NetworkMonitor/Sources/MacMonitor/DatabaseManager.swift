import Foundation
import SQLite3

/// 数据库管理器：管理 SQLite 数据库的初始化和基本操作
/// 数据存储在 ~/Library/Application Support/macMonitor/monitor.db
final class DatabaseManager {

    // MARK: - 属性

    private var db: OpaquePointer?

    /// 事件缓冲区 — 批量写入以减少 IO
    private var eventBuffer: [String] = []
    private let batchSize = 10
    private var flushTimer: DispatchSourceTimer?

    /// 数据库文件路径
    private(set) lazy var dbPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("macMonitor", isDirectory: true)
        // 确保目录存在
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("monitor.db").path
    }()

    // MARK: - 初始化与关闭

    /// 打开数据库并创建表结构
    func initialize() {
        let path = (dbPath as NSString).utf8String
        guard let cPath = path else {
            print("❌ 数据库路径无效")
            return
        }

        let status = sqlite3_open(cPath, &db)
        guard status == SQLITE_OK else {
            print("❌ 打开数据库失败: \(status)")
            db = nil
            return
        }

        createTables()
        startFlushTimer()
        print("✅ 数据库已就绪: \(dbPath)")
    }

    /// 关闭数据库连接
    func close() {
        flush() // 关闭前刷新缓冲区
        flushTimer?.cancel()
        flushTimer = nil
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    /// 数据库是否可用
    var isReady: Bool { db != nil }

    // MARK: - 事件写入

    /// 写入一条系统采样数据
    func writeSystemSample(timestamp: TimeInterval, cpuUsage: Double, memoryUsedMB: Int, memoryTotalMB: Int, networkRx: UInt64, networkTx: UInt64) {
        let extra: String
        if #available(macOS 10.15, *) {
            let dict: [String: Any] = [
                "cpu": cpuUsage,
                "memory_used_mb": memoryUsedMB,
                "memory_total_mb": memoryTotalMB,
                "net_rx": networkRx,
                "net_tx": networkTx,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let json = String(data: data, encoding: .utf8) {
                extra = escapeSQL(json)
            } else {
                extra = "NULL"
            }
        } else {
            extra = "NULL"
        }

        let escapedType = escapeSQL(EventType.systemSample.rawValue)
        let values = "(\(escapedType), '', '', \(timestamp), \(extra))"
        eventBuffer.append(values)

        if eventBuffer.count >= batchSize {
            flush()
        }
    }

    /// 写入一次击键批量数据（一条事件带计数）
    func writeKeyPressBatch(count: Int, timestamp: TimeInterval) {
        let escapedType = escapeSQL(EventType.keyPress.rawValue)
        let extra = escapeSQL("{\"count\":\(count)}")
        let values = "(\(escapedType), '', '', \(timestamp), \(extra))"
        eventBuffer.append(values)

        if eventBuffer.count >= batchSize {
            flush()
        }
    }

    func writeEvent(type: EventType, appName: String? = nil, bundleID: String? = nil, timestamp: TimeInterval) {
        // 使用 SQL 值转义避免注入
        let escapedType = escapeSQL(type.rawValue)
        let escapedApp = escapeSQL(appName ?? "")
        let escapedBundle = escapeSQL(bundleID ?? "")

        let values = "(\(escapedType), \(escapedApp), \(escapedBundle), \(timestamp), NULL)"
        eventBuffer.append(values)

        if eventBuffer.count >= batchSize {
            flush()
        }
    }

    /// 立即刷新缓冲区，将事件写入数据库
    func flush() {
        guard !eventBuffer.isEmpty, let db else { return }

        let values = eventBuffer.joined(separator: ",\n")
        let sql = "INSERT INTO events (event_type, app_name, app_bundle_id, timestamp, extra_data) VALUES \(values);"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("⚠️ 批量写入准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            print("⚠️ 批量写入失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        eventBuffer.removeAll()
    }

    /// 启动定时刷新（每30秒自动写入）
    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.flush()
        }
        timer.resume()
        flushTimer = timer
    }

    // MARK: - 辅助方法

    /// SQL 值转义（防止特殊字符破坏 SQL）
    private func escapeSQL(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "'", with: "''")
            .replacingOccurrences(of: "\\", with: "\\\\")
        return "'\(escaped)'"
    }

    // MARK: - 建表

    /// 创建所有需要的表（仅首次运行时执行）
    private func createTables() {
        let statements = [
            // 原始事件记录表
            """
            CREATE TABLE IF NOT EXISTS events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                event_type TEXT NOT NULL,
                app_name TEXT,
                app_bundle_id TEXT,
                window_title TEXT,
                timestamp REAL NOT NULL,
                extra_data TEXT
            );
            """,

            // 小时聚合统计表
            """
            CREATE TABLE IF NOT EXISTS stats_hourly (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                hour INTEGER NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT,
                total_seconds REAL DEFAULT 0,
                keypress_count INTEGER DEFAULT 0,
                cpu_avg REAL DEFAULT 0,
                memory_avg REAL DEFAULT 0,
                network_rx INTEGER DEFAULT 0,
                network_tx INTEGER DEFAULT 0,
                UNIQUE(date, hour, bundle_id)
            );
            """,

            // 每日汇总表
            """
            CREATE TABLE IF NOT EXISTS stats_daily (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL UNIQUE,
                total_active_seconds REAL DEFAULT 0,
                total_idle_seconds REAL DEFAULT 0,
                total_keypress INTEGER DEFAULT 0,
                screen_on_seconds REAL DEFAULT 0,
                screen_off_seconds REAL DEFAULT 0,
                power_on_battery_seconds REAL DEFAULT 0,
                power_on_ac_seconds REAL DEFAULT 0
            );
            """,
        ]

        for sql in statements {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard status == SQLITE_OK else {
                print("❌ 建表失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                print("❌ 建表执行失败: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
        }

        // 创建索引
        createIndexes()
    }

    /// 创建索引以优化查询性能
    private func createIndexes() {
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);",
            "CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);",
        ]

        for sql in indexes {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  sqlite3_step(stmt) == SQLITE_DONE else {
                print("⚠️ 索引创建失败: \(String(cString: sqlite3_errmsg(db)))")
                continue
            }
        }
    }
}
