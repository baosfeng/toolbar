#!/usr/bin/env swift

import Foundation
import SQLite3

// MARK: - 简单断言

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "") {
    if actual == expected {
        print("  ✅ \(message)")
    } else {
        print("  ❌ \(message) — 期望 \(expected)，实际 \(actual)")
        exit(1)
    }
}

// MARK: - 测试

print("🧪 MacMonitor 核心测试")
print("=====================")

// 1. 打开内存数据库
var db: OpaquePointer?
guard sqlite3_open(":memory:", &db) == SQLITE_OK else {
    print("❌ 无法打开数据库")
    exit(1)
}
print("✅ 打开内存数据库")

// 2. 创建表
var stmt: OpaquePointer?
var rc: Int32

let createEvents = """
    CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        app_name TEXT, app_bundle_id TEXT,
        window_title TEXT,
        timestamp REAL NOT NULL,
        extra_data TEXT
    );
"""
rc = sqlite3_prepare_v2(db, createEvents, -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "创建 events 表")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行建表 events")
sqlite3_finalize(stmt)

let createHourly = """
    CREATE TABLE IF NOT EXISTS stats_hourly (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL, hour INTEGER NOT NULL,
        app_name TEXT NOT NULL, bundle_id TEXT,
        total_seconds REAL DEFAULT 0, keypress_count INTEGER DEFAULT 0,
        cpu_avg REAL DEFAULT 0, memory_avg REAL DEFAULT 0,
        network_rx INTEGER DEFAULT 0, network_tx INTEGER DEFAULT 0,
        UNIQUE(date, hour, bundle_id)
    );
"""
rc = sqlite3_prepare_v2(db, createHourly, -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "创建 stats_hourly 表")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行建表 stats_hourly")
sqlite3_finalize(stmt)

let createDaily = """
    CREATE TABLE IF NOT EXISTS stats_daily (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,
        total_active_seconds REAL DEFAULT 0, total_idle_seconds REAL DEFAULT 0,
        total_keypress INTEGER DEFAULT 0,
        screen_on_seconds REAL DEFAULT 0, screen_off_seconds REAL DEFAULT 0,
        power_on_battery_seconds REAL DEFAULT 0, power_on_ac_seconds REAL DEFAULT 0
    );
"""
rc = sqlite3_prepare_v2(db, createDaily, -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "创建 stats_daily 表")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行建表 stats_daily")
sqlite3_finalize(stmt)

// 3. 插入事件数据
let testEvents: [(String, String, String, Double)] = [
    ("app_switch", "Chrome",   "com.google.Chrome",     1000.0),
    ("app_switch", "VSCode",   "com.microsoft.VSCode",  2000.0),
    ("app_switch", "Terminal", "com.apple.Terminal",    3000.0),
    ("screen_wake", "", "",  500.0),
    ("screen_sleep", "", "", 4000.0),
    ("key_press", "", "",    1500.0),
]

for (type, name, bundleID, ts) in testEvents {
    let sql = "INSERT INTO events (event_type, app_name, app_bundle_id, timestamp) VALUES ('\(type)', '\(name)', '\(bundleID)', \(ts));"
    rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    assertEqual(rc, SQLITE_OK, "插入: \(type)")
    assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行插入")
    sqlite3_finalize(stmt)
}
print("  ✅ 插入 \(testEvents.count) 条事件")

// 4. 验证总条数
rc = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM events;", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "查询总数")
assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取结果")
assertEqual(Int(sqlite3_column_int(stmt, 0)), testEvents.count, "总条数 = \(testEvents.count)")
sqlite3_finalize(stmt)

// 5. 验证按类型查询
rc = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM events WHERE event_type = 'app_switch';", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "查询 app_switch")
assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取结果")
assertEqual(Int(sqlite3_column_int(stmt, 0)), 3, "app_switch = 3")
sqlite3_finalize(stmt)

// 6. 验证按 BundleID 查询
rc = sqlite3_prepare_v2(db, "SELECT app_name FROM events WHERE app_bundle_id = 'com.google.Chrome';", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "查询 Chrome")
assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取结果")
assertEqual(String(cString: sqlite3_column_text(stmt, 0)), "Chrome", "应用名匹配")
sqlite3_finalize(stmt)

// 7. 验证时间范围
rc = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM events WHERE timestamp BETWEEN 1000 AND 3000;", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "查询时间范围")
assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取结果")
assertEqual(Int(sqlite3_column_int(stmt, 0)), 4, "区间内 4 条（Chrome:1000 + VSCode:2000 + Terminal:3000 + key_press:1500）")
sqlite3_finalize(stmt)

// 8. 创建索引
rc = sqlite3_prepare_v2(db, "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "创建索引 timestamp")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行索引")
sqlite3_finalize(stmt)

rc = sqlite3_prepare_v2(db, "CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "创建索引 event_type")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行索引")
sqlite3_finalize(stmt)

// 9. 清空并验证
rc = sqlite3_prepare_v2(db, "DELETE FROM events;", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "清空数据")
assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行清空")
sqlite3_finalize(stmt)

rc = sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM events;", -1, &stmt, nil)
assertEqual(rc, SQLITE_OK, "验证清空")
assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取结果")
assertEqual(Int(sqlite3_column_int(stmt, 0)), 0, "数据已清空")
sqlite3_finalize(stmt)

// 关闭
sqlite3_close(db)
print("✅ 关闭内存数据库")

print("\n=====================")
print("🎉 全部 9 项测试通过！")
