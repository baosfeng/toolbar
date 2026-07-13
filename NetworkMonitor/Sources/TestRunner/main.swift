import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - Assertion Helpers

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — expected \"\(expected)\", got \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        print("✅ \(message.isEmpty ? "not nil" : message)")
    } else {
        print("❌ \(file):\(line) — expected not nil\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

// MARK: - Test formatSpeedShort

let speedCases: [(bps: Double, expected: String)] = [
    (0.0, "0B"),
    (500.0, "500B"),
    (1_500.0, "2K"),
    (42_000.0, "42K"),
    (999_000.0, "999K"),
    (1_200_000.0, "1.2M"),
    (55_000_000.0, "55.0M"),
    (2_300_000_000.0, "2.3G"),
]
print("🧪 Testing formatSpeedShort...")
for (bps, expected) in speedCases {
    assertEqual(formatSpeedShort(bps), expected)
}

// MARK: - Test parseNettopLine

print("\n🧪 Testing parseNettopLine...")

let line1 = "23:46:47.674162 Google Chrome H.51129                                   16218            4096"
let r1 = parseNettopLine(line1)
assertNotNil(r1, "should parse normal line")
if let r = r1 {
    assertEqual(r.name, "Google Chrome H", "name")
    assertEqual(r.pid, Int32(51129), "pid")
    assertEqual(r.bytesIn, UInt64(16218), "bytesIn")
    assertEqual(r.bytesOut, UInt64(4096), "bytesOut")
}

let lineMulti = "23:46:48.123456 Microsoft Excel T.12345                                   98765           43210"
let rMulti = parseNettopLine(lineMulti)
assertNotNil(rMulti, "multi-word name")
if let r = rMulti {
    assertEqual(r.name, "Microsoft Excel T", "multi-word name")
    assertEqual(r.pid, Int32(12345), "multi-word pid")
    assertEqual(r.bytesIn, UInt64(98765), "multi-word bytesIn")
}

let line2 = "23:46:47.674152 airportd.649                                                                                   0               0"
let r2 = parseNettopLine(line2)
assertNotNil(r2, "should parse zero line")
if let r = r2 {
    assertEqual(r.name, "airportd")
    assertEqual(r.bytesIn, UInt64(0))
}

let line3 = "23:46:47.674157 mDNSResponder.689                                                                  105434952       59651139"
let r3 = parseNettopLine(line3)
assertNotNil(r3, "should parse large numbers")
if let r = r3 {
    assertEqual(r.bytesIn, UInt64(105434952))
    assertEqual(r.bytesOut, UInt64(59651139))
}

let header = parseNettopLine("time                                                                            interface   type        bytes_in       bytes_out   rcvsize  tc_class arch")
assertEqual(header, nil, "header should return nil")

let empty = parseNettopLine("")
assertEqual(empty, nil, "empty should return nil")

// MARK: - Test sparkline

print("\n🧪 Testing sparkline...")

assertEqual(sparkline(from: []), "", "empty")

let allSame = sparkline(from: [0, 0, 0])
assertEqual(allSame, "▁▁▁", "all zero")

let linear = sparkline(from: [0, 1, 2, 3, 4, 5, 6, 7])
assertEqual(linear, "▁▂▃▄▅▆▇█", "linear 0-7")

let single = sparkline(from: [42])
assertEqual(single, "█", "single peak")

let desc = sparkline(from: [5, 4, 3, 2, 1, 0])
assertEqual(desc, "█▆▅▃▂▁", "descending")

// MARK: - Test formatBytesFull

print("\n🧪 Testing formatBytesFull...")
assertEqual(formatBytesFull(0), "Zero KB")
assertEqual(formatBytesFull(1024), "1 KB")
assertEqual(formatBytesFull(1_000_000), "1 MB")
assertEqual(formatBytesFull(2_500_000_000), "2.5 GB")

// MARK: - Test DatabaseManager (in-memory)

print("\n🧪 Testing DatabaseManager...")

// Helper: run query on DatabaseManager and collect results as rows of [String?]
func collectQuery(_ db: DatabaseManager, sql: String) -> [[String?]] {
    var rows: [[String?]] = []
    db.query(sql: sql) { stmt in
        var row: [String?] = []
        let colCount = sqlite3_column_count(stmt)
        for i in 0..<colCount {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL {
                row.append(nil)
            } else if let cStr = sqlite3_column_text(stmt, i) {
                row.append(String(cString: cStr))
            } else {
                row.append(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

// RED: Write test, verify it works (code exists, so it should pass)
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    assertEqual(db.isReady, true, "in-memory db should be ready")

    // Test: writeEvent + flush → data in events table
    db.writeEvent(type: .appOpen, appName: "TestApp", bundleID: "com.test", timestamp: 1000)
    db.writeEvent(type: .appClose, appName: "TestApp", bundleID: "com.test", timestamp: 2000)
    db.flush()

    let rows = collectQuery(db, sql: "SELECT event_type, app_name, app_bundle_id FROM events ORDER BY timestamp ASC")
    assertEqual(rows.count, 2, "should have 2 events")

    if rows.count >= 2 {
        assertEqual(rows[0][0], "app_open", "first event type")
        assertEqual(rows[0][1], "TestApp", "first event app name")
        assertEqual(rows[0][2], "com.test", "first event bundle id")
        assertEqual(rows[1][0], "app_close", "second event type")
    }

    print("✅ writeEvent + flush works")
}

// Test: writeSystemSample + flush + query extra_data JSON
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    db.writeSystemSample(timestamp: 3000, cpuUsage: 45.5, memoryUsedMB: 4096, memoryTotalMB: 16384, networkRx: 1000, networkTx: 500)
    db.flush()

    let rows = collectQuery(db, sql: "SELECT event_type, extra_data FROM events")
    assertEqual(rows.count, 1, "should have 1 system sample")
    if rows.count >= 1 {
        assertEqual(rows[0][0], "system_sample", "event type is system_sample")
        assertNotNil(rows[0][1], "extra_data should not be nil")
        if let json = rows[0][1] {
            // Verify JSON content
            assertEqual(json.contains("\"cpu\":45.5") || json.contains("\"cpu\":45.5"), true, "extra_data contains cpu")
            assertEqual(json.contains("\"memory_used_mb\":4096"), true, "extra_data contains memory_used_mb")
        }
    }

    print("✅ writeSystemSample + flush works")
}

// Test: writeKeyPressBatch + flush
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    db.writeKeyPressBatch(count: 42, timestamp: 4000)
    db.flush()

    let rows = collectQuery(db, sql: "SELECT event_type, extra_data FROM events WHERE event_type = 'key_press'")
    assertEqual(rows.count, 1, "should have 1 key_press event")
    if rows.count >= 1 {
        assertEqual(rows[0][0], "key_press", "event type is key_press")
        assertNotNil(rows[0][1], "extra_data should not be nil")
        if let json = rows[0][1] {
            assertEqual(json.contains("\"count\":42"), true, "extra_data contains count")
        }
    }

    print("✅ writeKeyPressBatch + flush works")
}

// Test: query with empty result
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let rows = collectQuery(db, sql: "SELECT * FROM events")
    assertEqual(rows.count, 0, "empty table should return 0 rows")
    print("✅ query returns empty for empty table")
}

// MARK: - Test StatsProvider

print("\n🧪 Testing StatsProvider...")

do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let statsProvider = StatsProvider(database: db)
    let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970

    // Insert test data via db.query (handler not called for INSERT)
    let switchSQL = "INSERT INTO events (event_type, app_name, app_bundle_id, timestamp) VALUES ('app_switch', 'Browser', 'com.browser', \(startOfDay + 100)), ('app_switch', 'Editor', 'com.editor', \(startOfDay + 200)), ('app_switch', 'Browser', 'com.browser', \(startOfDay + 300)), ('app_switch', 'Editor', 'com.editor', \(startOfDay + 350))"
    db.query(sql: switchSQL) { _ in }

    // key_press event with count
    db.query(sql: "INSERT INTO events (event_type, extra_data, timestamp) VALUES ('key_press', '{\"count\":10}', \(startOfDay + 150))") { _ in }

    // screen events
    db.query(sql: "INSERT INTO events (event_type, timestamp) VALUES ('screen_wake', \(startOfDay + 50)), ('screen_sleep', \(startOfDay + 200))") { _ in }

    // system sample
    db.query(sql: "INSERT INTO events (event_type, extra_data, timestamp) VALUES ('system_sample', '{\"cpu\":60.0,\"memory_used_mb\":2048,\"memory_total_mb\":16384,\"net_rx\":50000,\"net_tx\":25000}', \(startOfDay + 250))") { _ in }

    // Debug: verify data was inserted
    var totalEvents: Int32 = 0
    db.query(sql: "SELECT COUNT(*) FROM events") { stmt in
        totalEvents = sqlite3_column_int(stmt, 0)
    }
    assertEqual(Int(totalEvents), 8, "should have 8 events in table")

    // Debug: check app_switch events specifically
    var switchCount: Int32 = 0
    var bundleIDs: [String] = []
    db.query(sql: "SELECT event_type, app_bundle_id FROM events WHERE event_type = 'app_switch'") { stmt in
        switchCount += 1
        if let cStr = sqlite3_column_text(stmt, 1) {
            bundleIDs.append(String(cString: cStr))
        }
    }
    assertEqual(Int(switchCount), 4, "should have 4 app_switch events")
    assertEqual(bundleIDs.count, 4, "should have 4 bundle IDs")
    assertEqual(bundleIDs.filter { $0 == "com.browser" }.count, 2, "browser should appear twice")
    assertEqual(bundleIDs.filter { $0 == "com.editor" }.count, 2, "editor should appear twice")

    let stats = statsProvider.fetchTodayStats()

    assertEqual(stats.activeSeconds > 0, true, "active seconds should be > 0")
    assertEqual(stats.keyPressCount, 10, "key press count should be 10")
    assertEqual(stats.screenOnSeconds > 0, true, "screen on seconds should be > 0")
    assertEqual(stats.screenOffSeconds, 0, "screen off seconds should be 0 (no matching pair)")
    assertEqual(stats.appRanking.count, 2, "should have 2 apps in ranking")
    assertEqual(stats.cpuUsage, 60.0, "cpu usage should be 60.0")
    assertEqual(stats.memoryUsedMB, 2048, "memory used should be 2048 MB")
    assertEqual(stats.netDownloadSpeed, 50000, "net download should be 50000")
    assertEqual(stats.netUploadSpeed, 25000, "net upload should be 25000")
    assertEqual(stats.memoryTotalMB > 0, true, "total memory should be > 0")

    print("✅ StatsProvider.fetchTodayStats() works with test data")
}

// Test: StatsProvider with no data → empty stats
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let statsProvider = StatsProvider(database: db)
    let stats = statsProvider.fetchTodayStats()

    assertEqual(stats.activeSeconds, 0, "no events → 0 active seconds")
    assertEqual(stats.keyPressCount, 0, "no events → 0 key presses")
    assertEqual(stats.cpuUsage, 0, "no events → 0 cpu usage")
    assertEqual(stats.appRanking.isEmpty, true, "no events → empty ranking")

    print("✅ StatsProvider.fetchTodayStats() returns empty stats with no data")
}

// MARK: - Test ReportGenerator

print("\n🧪 Testing ReportGenerator...")

do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    let statsProvider = StatsProvider(database: db)
    let reportGen = ReportGenerator(database: db, statsProvider: statsProvider)

    // Insert some data
    let startOfDay = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
    db.query(sql: "INSERT INTO events (event_type, app_name, app_bundle_id, timestamp) VALUES ('app_switch', 'TestApp', 'com.test', \(startOfDay + 100)), ('app_switch', 'TestApp', 'com.test', \(startOfDay + 120))") { _ in }
    db.query(sql: "INSERT INTO events (event_type, extra_data, timestamp) VALUES ('key_press', '{\"count\":5}', \(startOfDay + 150))") { _ in }
    db.query(sql: "INSERT INTO events (event_type, extra_data, timestamp) VALUES ('system_sample', '{\"cpu\":30.0,\"memory_used_mb\":1024,\"memory_total_mb\":16384,\"net_rx\":1000,\"net_tx\":500}', \(startOfDay + 200))") { _ in }

    let reportPath = reportGen.generateDailyReport()
    assertNotNil(reportPath, "daily report should be generated")
    if let path = reportPath {
        assertEqual(FileManager.default.fileExists(atPath: path), true, "report file should exist")
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            assertEqual(content.contains("TestApp"), true, "report should contain app name")
            assertEqual(content.contains("5"), true, "report should contain keypress count")
            print("✅ ReportGenerator.generateDailyReport() works")
        } else {
            print("❌ cannot read report file")
            exit(1)
        }
    }
}

// MARK: - Done

print("\n🎉 所有测试通过！")
