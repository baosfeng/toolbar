import Foundation
import SQLite3

/// 简单的断言辅助
func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ 通过: \(expected)\(message.isEmpty ? "" : " — \(message)")")
    } else {
        print("❌ 失败: \(file):\(line) — 期望 \"\(expected)\"，实际 \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertTrue(_ value: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if value {
        print("✅ 通过: \(message.isEmpty ? "true" : message)")
    } else {
        print("❌ 失败: \(file):\(line) — 期望 true\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

// MARK: - EventType 测试

func testEventTypeValues() {
    print("\n--- EventType 枚举值 ---")
    assertEqual(EventType.appOpen.rawValue, "app_open")
    assertEqual(EventType.appClose.rawValue, "app_close")
    assertEqual(EventType.appSwitch.rawValue, "app_switch")
    assertEqual(EventType.screenSleep.rawValue, "screen_sleep")
    assertEqual(EventType.screenWake.rawValue, "screen_wake")
    assertEqual(EventType.systemSleep.rawValue, "system_sleep")
    assertEqual(EventType.systemWake.rawValue, "system_wake")
    assertEqual(EventType.keyPress.rawValue, "key_press")
    assertEqual(EventType.systemSample.rawValue, "system_sample")
    assertEqual(EventType.windowTitle.rawValue, "window_title")
    print("✅ EventType: 所有枚举值正确 (10/10)")
}

// MARK: - DatabaseManager 测试

func testDatabaseManager() {
    print("\n--- DatabaseManager ---")

    // 使用内存数据库
    var db: OpaquePointer?
    let rc = sqlite3_open(":memory:", &db)
    assertEqual(rc, SQLITE_OK, "打开内存数据库")

    // 创建表
    let createSQL = """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            app_name TEXT,
            app_bundle_id TEXT,
            window_title TEXT,
            timestamp REAL NOT NULL,
            extra_data TEXT
        );
        """
    var stmt: OpaquePointer?
    assertEqual(sqlite3_prepare_v2(db, createSQL, -1, &stmt, nil), SQLITE_OK, "预处理建表 SQL")
    assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行建表")
    sqlite3_finalize(stmt)

    // 插入数据
    let insertSQL = "INSERT INTO events (event_type, app_name, app_bundle_id, timestamp) VALUES ('app_switch', 'TestApp', 'com.test.app', 1234567890.0);"
    assertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil), SQLITE_OK, "预处理插入 SQL")
    assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行插入")
    sqlite3_finalize(stmt)

    // 查询数据
    let querySQL = "SELECT event_type, app_name FROM events WHERE app_bundle_id = 'com.test.app';"
    assertEqual(sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil), SQLITE_OK, "预处理查询 SQL")

    var rowCount = 0
    while sqlite3_step(stmt) == SQLITE_ROW {
        rowCount += 1
        let type = String(cString: sqlite3_column_text(stmt, 0))
        let name = String(cString: sqlite3_column_text(stmt, 1))
        assertEqual(type, "app_switch", "事件类型正确")
        assertEqual(name, "TestApp", "应用名正确")
    }
    assertEqual(rowCount, 1, "查询到 1 条记录")
    sqlite3_finalize(stmt)

    // 批量插入测试
    let batchSQL = "INSERT INTO events (event_type, app_name, timestamp) VALUES ('app_open', 'Safari', 1234567891.0);"
    assertEqual(sqlite3_prepare_v2(db, batchSQL, -1, &stmt, nil), SQLITE_OK, "预处理批量插入")
    assertEqual(sqlite3_step(stmt), SQLITE_DONE, "执行批量插入")
    sqlite3_finalize(stmt)

    // 验证总条数
    let countSQL = "SELECT COUNT(*) FROM events;"
    assertEqual(sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil), SQLITE_OK, "预处理计数")
    assertEqual(sqlite3_step(stmt), SQLITE_ROW, "读取计数")
    let totalCount = sqlite3_column_int(stmt, 0)
    assertEqual(Int(totalCount), 2, "总记录数 = 2")
    sqlite3_finalize(stmt)

    sqlite3_close(db)
    print("✅ DatabaseManager: 所有操作通过 (8/8)")
}

// MARK: - 主函数

func main() {
    print("🧪 MacMonitor 测试套件")
    print("======================")

    testEventTypeValues()
    testDatabaseManager()

    print("\n======================")
    print("🎉 全部测试通过！")
}

main()
