import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - 事务原语的契约

/// 事务原语（`withTransaction`）的三条硬契约：
/// 正常返回 = 整体提交 · 抛出 = 整体回滚（写了一半也不留半截）· 嵌套不再开第二个事务。
func runDatabaseTransactionTests() {
    print("🧪 Testing 事务原语（提交 / 回滚 / 嵌套）...")

    // 1) 正常提交：事务体内的两行都落库
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        do {
            try db.withTransaction { conn in
                try insertProbeItem(conn, key: "tx-commit-1")
                try insertProbeItem(conn, key: "tx-commit-2")
            }
        } catch {
            assertEqual("事务提交失败: \(error)", "", "正常路径不应抛错")
        }
        assertEqual(db.clipboardItemCount(), 2, "提交后两行都在")
        print("✅ 事务提交 works")
    }

    // 2) 中途抛错：写了一半又抛，两半都不许落库
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        var threw = false
        do {
            try db.withTransaction { conn in
                try insertProbeItem(conn, key: "tx-rollback-1")
                try insertProbeItem(conn, key: "tx-rollback-2")
                throw DatabaseOperationError("写一半就失败")
            }
        } catch {
            threw = true
            assertContains("\(error)", "写一半就失败", "原始错误向上传播")
        }
        assertEqual(threw, true, "事务中途抛错必须向上传播")
        assertEqual(db.clipboardItemCount(), 0, "回滚后一行都没落库（两半都没留下）")
        print("✅ 事务中途抛错整体回滚 works")
    }

    // 3) 嵌套：同一条连接上再调 withTransaction 不再开事务（内层不提交）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        do {
            try db.withTransaction { conn in
                try insertProbeItem(conn, key: "tx-nested-a")
                try NetworkMonitorCore.withTransaction(conn) { inner in
                    try insertProbeItem(inner, key: "tx-nested-b")
                }
                try insertProbeItem(conn, key: "tx-nested-c")
            }
        } catch {
            assertEqual("嵌套事务失败: \(error)", "", "嵌套不应报错（内层不重复开事务）")
        }
        assertEqual(db.clipboardItemCount(), 3, "嵌套事务内三行一起提交")
        print("✅ 嵌套 withTransaction 不重复开事务 works")
    }

    // 3b 内层正常、外层之后抛错 → 内层那行必须跟着外层一起回滚（证明内层没有自己提交）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        do {
            try db.withTransaction { conn in
                try insertProbeItem(conn, key: "tx-nested-rollback-a")
                try NetworkMonitorCore.withTransaction(conn) { inner in
                    try insertProbeItem(inner, key: "tx-nested-rollback-b")
                }
                throw DatabaseOperationError("外层失败")
            }
        } catch {
            _ = error
        }
        assertEqual(db.clipboardItemCount(), 0, "内层写入随外层一起回滚（内层未独立提交）")
        print("✅ 嵌套内层不提交 works")
    }
}

// MARK: - 删板原子性（T1 防复发）

/// T1：删板 = 删条目 + 删板行，必须在同一个事务里。
/// 用故障注入模拟「条目已删、板行删除失败」，断言板与条目都还在。
func runBoardDeleteAtomicityTests() {
    print("🧪 Testing 删板原子性（T1 防复发）...")
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        guard let board = db.createBoard(name: "原子性"),
              let inside = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "atomic-inside",
                                                               preview: "板内", imagePath: "/tmp/atomic-inside.png",
                                                               imageWidth: 8, imageHeight: 8)),
              let outside = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "atomic-outside", text: "板外")),
              db.moveItemToBoard(itemID: inside.id, boardID: board.id) else {
            assertEqual(false, true, "原子性用例的前置数据准备失败")
            return
        }

        // 故障注入：条目已删，此时板行删除失败 → 整体回滚
        db.deleteBoardFaultProbe = { true }
        let failed = db.deleteBoard(id: board.id)
        assertEqual(failed.isEmpty, true, "失败时返回空（不误导上层去回收图片）")
        assertEqual(db.fetchBoards().count, 1, "板仍在（回滚）")
        assertEqual(db.fetchClipboardItem(id: inside.id) != nil, true, "板内条目仍在（回滚）")
        assertEqual(db.clipboardItemCount(), 2, "两条条目都还在")
        print("✅ 删条目后失败 → 板与条目都回滚 works")

        // 撤掉注入：同一个板再删一次，正常返回被删行（既有不变量：供 ClipboardImageGC 回收图片）
        db.deleteBoardFaultProbe = nil
        let doomed = db.deleteBoard(id: board.id)
        assertEqual(doomed.map(\.id), [inside.id], "成功后返回板内被删条目")
        assertEqual(db.fetchBoards().isEmpty, true, "板已删除")
        assertEqual(db.fetchClipboardItem(id: outside.id) != nil, true, "板外条目不受影响")
        print("✅ 删板成功路径不变量保留 works")
    }
}

// MARK: - 迁移登记表

/// 迁移登记表的契约：order 乱序登记也按 order 执行 · 同一 migration 只跑一次（幂等）·
/// 没登记的 migration 不执行 · 失败即停且不写日志。
func runMigrationRegistryTests() {
    print("🧪 Testing 迁移登记表（order / 幂等 / 缺登记 / 失败即停）...")

    // 1) 乱序登记 → 按 order 升序执行
    do {
        let recorder = MigrationOrderRecorder()
        let registry = MigrationRegistry(logger: AppContext.shared.logger)
        registry.register(ProbeMigration(order: 30, tag: "c", recorder: recorder))
        registry.register(ProbeMigration(order: 10, tag: "a", recorder: recorder))
        registry.register(ProbeMigration(order: 20, tag: "b", recorder: recorder))
        assertEqual(registry.all.map(\.order), [10, 20, 30], "all 按 order 升序")
        withProbeConnection { conn in
            assertEqual(registry.runAll(on: conn), true, "runAll 成功")
            assertEqual(recorder.recorded, ["a", "b", "c"], "执行顺序 = order 升序（与注册顺序无关）")
            assertEqual(registry.executedIdentifiers(conn), Set(["probe-a", "probe-b", "probe-c"]), "三条都写进迁移日志")
        }
        print("✅ 登记表按 order 执行 works")
    }

    // 2) 幂等：同一 registry 再跑一次不再执行；force 重跑（各迁移自身幂等）
    do {
        let recorder = MigrationOrderRecorder()
        let registry = MigrationRegistry(logger: AppContext.shared.logger)
        registry.register(ProbeMigration(order: 1, tag: "once", recorder: recorder))
        withProbeConnection { conn in
            assertEqual(registry.runAll(on: conn), true, "首次执行成功")
            assertEqual(recorder.count, 1, "首次执行跑了 1 次")
            assertEqual(registry.runAll(on: conn), true, "重复执行返回成功")
            assertEqual(recorder.count, 1, "重复执行不重跑（迁移日志已记）")
            assertEqual(registry.runAll(on: conn, force: true), true, "force 重跑成功")
            assertEqual(recorder.count, 2, "force 忽略日志重跑一次")
        }
        print("✅ 迁移幂等 + force 重跑 works")
    }

    // 3) 缺登记不执行：没 register 的 migration 一行都不跑
    do {
        let unregistered = MigrationOrderRecorder()
        let registry = MigrationRegistry(logger: AppContext.shared.logger)
        registry.register(ProbeMigration(order: 1, tag: "registered", recorder: MigrationOrderRecorder()))
        _ = unregistered
        withProbeConnection { conn in
            assertEqual(registry.runAll(on: conn), true, "只跑已登记的迁移")
            let tables = tableNames(conn).filter { $0.hasPrefix("probe_table_") }
            assertEqual(tables, ["probe_table_registered"], "只有登记过的那条迁移建了表")
        }
        print("✅ 缺登记不执行 works")
    }

    // 4) 协议口径：装配层只依赖 `any DatabaseService` 也能开事务（不必知道 DatabaseManager）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let service: any DatabaseService = db
        do {
            try service.withTransaction { conn in
                try insertProbeItem(conn, key: "tx-protocol-1")
            }
        } catch {
            assertEqual("协议事务失败: \(error)", "", "协议上的 withTransaction 不应抛错")
        }
        assertEqual(db.clipboardItemCount(), 1, "经 DatabaseService 协议提交的写入已落库")
        print("✅ 协议层 withTransaction 可用 works")
    }

    // 5) 失败即停：抛错的那条不写日志、后续 migration 不执行
    do {
        let recorder = MigrationOrderRecorder()
        let registry = MigrationRegistry(logger: AppContext.shared.logger)
        registry.register(FailingMigration(order: 1))
        registry.register(ProbeMigration(order: 2, tag: "after-fail", recorder: recorder))
        withProbeConnection { conn in
            assertEqual(registry.runAll(on: conn), false, "迁移失败返回 false")
            assertEqual(recorder.count, 0, "失败之后的迁移不再执行")
            assertEqual(registry.executedIdentifiers(conn).contains("probe-fail"), false, "失败的那条不写日志（下次启动重试）")
        }
        print("✅ 迁移失败即停 works")
    }

    // 5) 应用侧登记表自洽：真实注册表必须有两条迁移（剪贴板 + Harness 索引）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let registry = db.makeMigrationRegistry()
        assertEqual(registry.all.count, 2, "应用登记了 2 条迁移")
        assertEqual(registry.all.map(\.identifier), ["clipboard.schema.ladder", "harness.schema.create"], "迁移 id 与顺序稳定")
        print("✅ 应用侧登记表自洽 works")
    }
}

// MARK: - 测试辅助

/// 迁移执行顺序记录器（跨线程安全）
private final class MigrationOrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ tag: String) {
        lock.lock()
        entries.append(tag)
        lock.unlock()
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    var count: Int { recorded.count }
}

private struct ProbeMigration: SchemaMigration {
    let order: Int32
    let tag: String
    let recorder: MigrationOrderRecorder

    var identifier: String { "probe-\(tag)" }

    func migrate(_ db: OpaquePointer) throws {
        recorder.record(tag)
        guard sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS probe_table_\(tag) (v INTEGER);", nil, nil, nil) == SQLITE_OK else {
            throw DatabaseOperationError("探针建表失败")
        }
    }
}

private struct FailingMigration: SchemaMigration {
    let order: Int32
    var identifier: String { "probe-fail" }

    func migrate(_ db: OpaquePointer) throws {
        _ = db
        throw DatabaseOperationError("探针迁移故意失败")
    }
}

/// 开一条独立的内存连接跑登记表（不碰 DatabaseManager 的写连接）
private func withProbeConnection(_ body: (OpaquePointer) -> Void) {
    var conn: OpaquePointer?
    guard sqlite3_open(":memory:", &conn) == SQLITE_OK, let conn else {
        assertEqual(false, true, "探针内存连接打开失败")
        return
    }
    defer { sqlite3_close(conn) }
    body(conn)
}

/// 当前连接的库内表名
private func tableNames(_ conn: OpaquePointer) -> [String] {
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(conn, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;", -1, &stmt, nil) == SQLITE_OK else {
        return []
    }
    var names: [String] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let text = sqlite3_column_text(stmt, 0) { names.append(String(cString: text)) }
    }
    return names
}

/// 插一条最小可用的剪贴板行（列有默认值的都不填）
private func insertProbeItem(_ conn: OpaquePointer, key: String) throws {
    let sql = """
    INSERT INTO clipboard_items (id, kind, preview, content_hash, created_at)
    VALUES (?, 'text', '', ?, 0);
    """
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_prepare_v2(conn, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw DatabaseOperationError("探针插入准备失败: \(String(cString: sqlite3_errmsg(conn)))")
    }
    sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    sqlite3_bind_text(stmt, 2, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    guard sqlite3_step(stmt) == SQLITE_DONE else {
        throw DatabaseOperationError("探针插入失败: \(String(cString: sqlite3_errmsg(conn)))")
    }
}
