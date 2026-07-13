import Foundation
import SQLite3

/// 数据库管理器：管理 SQLite 数据库的初始化和基本操作
/// 数据存储在 ~/Library/Application Support/macMonitor/monitor.db
///
/// 线程安全说明：
/// - 所有 sqlite3_* 调用通过串行队列 `serialQueue` 访问，保证单线程操作 db 指针
/// - `PRAGMA mmap_size=0` 禁用 mmap，避免 Apple 平台 mmap/purgeable 缓存导致的死锁
/// - `PRAGMA journal_mode=WAL` 启用 WAL 模式，读写不互相阻塞
///
/// 测试支持：
/// - `initializeInMemory()` 使用 `:memory:` 数据库，适合单元测试
public final class DatabaseManager: @unchecked Sendable {

    // MARK: - 属性

    private var db: OpaquePointer?

    /// 串行队列 — 所有数据库操作在此队列上执行
    private let serialQueue = DispatchQueue(label: "com.example.NetworkMonitor.database")

    /// 事件缓冲区 — 批量写入以减少 IO（仅在 serialQueue 上读写）
    private var eventBuffer: [String] = []
    private var flushTimer: DispatchSourceTimer?

    /// 数据库文件路径
    public private(set) lazy var dbPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("macMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("monitor.db").path
    }()

    public init() {}

    // MARK: - 初始化与关闭

    /// 打开数据库并创建表结构（基于文件系统默认路径）
    public func initialize() {
        serialQueue.sync {
            _initialize()
        }
    }

    /// 打开内存数据库（仅用于测试，不启动 flush 定时器）
    public func initializeInMemory() {
        serialQueue.sync {
            _openInMemory()
        }
    }

    private func _initialize() {
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

        // 禁用 mmap — 避免 purgeableCacheUnpin 死锁/活锁（Apple 平台特有 bug）
        applyPragma("mmap_size", value: "0")
        // 启用 WAL 模式 — 读写不互相阻塞
        applyPragma("journal_mode", value: "WAL")

        createTables()
        startFlushTimer()
        print("✅ 数据库已就绪: \(dbPath)")
    }

    private func _openInMemory() {
        let status = sqlite3_open(":memory:", &db)
        guard status == SQLITE_OK else {
            print("❌ 打开内存数据库失败: \(status)")
            db = nil
            return
        }

        createTables()
        print("✅ 内存数据库已就绪")
    }

    /// 执行 PRAGMA 语句
    private func applyPragma(_ name: String, value: String) {
        guard let db else { return }
        let sql = "PRAGMA \(name)=\(value);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_DONE else {
            print("⚠️ PRAGMA \(name) 设置失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
    }

    /// 关闭数据库连接
    public func close() {
        serialQueue.sync {
            _close()
        }
    }

    private func _close() {
        flushTimer?.cancel()
        flushTimer = nil
        _flush()
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    /// 数据库是否可用
    public var isReady: Bool {
        serialQueue.sync { db != nil }
    }

    /// 执行查询，每行调用一次 handler
    public func query(sql: String, handler: @escaping (OpaquePointer) -> Void) {
        serialQueue.sync {
            _query(sql: sql, handler: handler)
        }
    }

    private func _query(sql: String, handler: (OpaquePointer) -> Void) {
        guard let db else { return }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            handler(stmt!)
        }
    }

    // MARK: - 事件写入

    /// 写入一条系统采样数据
    public func writeSystemSample(timestamp: TimeInterval, cpuUsage: Double, memoryUsedMB: Int, memoryTotalMB: Int, networkRx: UInt64, networkTx: UInt64) {
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
        let values = "(\(escapedType), '', '', '', \(timestamp), \(extra))"

        serialQueue.async { [weak self] in
            self?.eventBuffer.append(values)
        }
    }

    /// 写入一次击键批量数据（一条事件带计数）
    public func writeKeyPressBatch(count: Int, timestamp: TimeInterval) {
        let escapedType = escapeSQL(EventType.keyPress.rawValue)
        let extra = escapeSQL("{\"count\":\(count)}")
        let values = "(\(escapedType), '', '', '', \(timestamp), \(extra))"

        serialQueue.async { [weak self] in
            self?.eventBuffer.append(values)
        }
    }

    public func writeEvent(type: EventType, appName: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, timestamp: TimeInterval) {
        let escapedType = escapeSQL(type.rawValue)
        let escapedApp = escapeSQL(appName ?? "")
        let escapedBundle = escapeSQL(bundleID ?? "")
        let escapedTitle = escapeSQL(windowTitle ?? "")

        let values = "(\(escapedType), \(escapedApp), \(escapedBundle), \(escapedTitle), \(timestamp), NULL)"

        serialQueue.async { [weak self] in
            self?.eventBuffer.append(values)
        }
    }

    /// 立即刷新缓冲区，将事件写入数据库
    public func flush() {
        serialQueue.sync {
            _flush()
        }
    }

    private func _flush() {
        guard !eventBuffer.isEmpty, let db else { return }

        let values = eventBuffer.joined(separator: ",\n")
        let sql = "INSERT INTO events (event_type, app_name, app_bundle_id, window_title, timestamp, extra_data) VALUES \(values);"

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
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?._flush()
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
