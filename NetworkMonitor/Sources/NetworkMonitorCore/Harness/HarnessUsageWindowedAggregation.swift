import Foundation
import SQLite3

// MARK: - 按范围聚合（项目 / 模型）

/// 按范围的项目与模型聚合 —— 与累计口径各算一份，页面只取当前范围那份
///
/// 性能实测（本机真实索引库 133,312 行，monitor.db，见交接文档）：
/// - 三档分开查（今日 46ms + 7 天 80ms + 30 天 198ms / 模型同理）≈ 每轮 320ms+
/// - **合并成单条 SQL 用 CASE WHEN 分窗口**：项目 82ms + 模型 104ms ≈ 186ms，
///   只比现状（两条累计查询 178~250ms）略高，却换来「切范围零查询 + 与 Hero 同口径」。
/// 因此三档一次算完并随快照缓存；不做按需惰性查。
extension DatabaseManager {

    /// 三档窗口的项目 / 模型聚合（顺序同 `HarnessUsageWindow.allCases`）
    func harnessWindowedUsage(_ db: OpaquePointer, now: Date) -> [HarnessWindowedUsage] {
        let windows = HarnessRangeWindows.allWindows(now: now)
        return windows.map { entry in
            HarnessWindowedUsage(
                window: entry.window,
                projects: harnessProjects(db, window: entry.range),
                models: harnessModels(db, window: entry.range),
                projectTotals: harnessProjectTotals(db, window: entry.range),
                modelTotals: harnessModelTotals(db, window: entry.range)
            )
        }
    }

    // MARK: - SQL

    /// 窗口内的项目聚合（cwd 为空的事件不归属任何项目；按总 token 降序）
    private func harnessProjects(_ db: OpaquePointer,
                                 window: HarnessMsWindow) -> [HarnessProjectUsage] {
        let sql = """
        SELECT cwd, COUNT(DISTINCT session_id), COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        WHERE cwd <> '' AND ts_ms >= ? AND ts_ms < ?
        GROUP BY cwd
        ORDER BY (SUM(uncached_in) + SUM(output) + SUM(cache_read) + SUM(cache_write)) DESC, cwd ASC;
        """
        return queryProjects(db, sql: sql, window: window)
    }

    /// 窗口内的模型聚合
    private func harnessModels(_ db: OpaquePointer,
                               window: HarnessMsWindow) -> [HarnessModelUsage] {
        let sql = """
        SELECT provider, model, COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*)
        FROM harness_token_event
        WHERE ts_ms >= ? AND ts_ms < ?
        GROUP BY provider, model
        ORDER BY (SUM(uncached_in) + SUM(output) + SUM(cache_read) + SUM(cache_write)) DESC, model ASC;
        """
        return queryModels(db, sql: sql, window: window)
    }

    /// 窗口内全部项目的 token 合计（占比分母；不能用 TopN 行求和，否则占比虚高）
    private func harnessProjectTotals(_ db: OpaquePointer,
                                      window: HarnessMsWindow) -> HarnessTokenUsage {
        harnessSum(db, fromMs: window.fromMs, toMs: window.toMs, onlyWithProject: true)
    }

    /// 窗口内全部模型的 token 合计（占比分母）
    private func harnessModelTotals(_ db: OpaquePointer,
                                    window: HarnessMsWindow) -> HarnessTokenUsage {
        harnessSum(db, fromMs: window.fromMs, toMs: window.toMs)
    }

    // MARK: - 行解析

    private func queryProjects(_ db: OpaquePointer, sql: String,
                               window: HarnessMsWindow) -> [HarnessProjectUsage] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard prepareWindowed(db, sql: sql, stmt: &stmt, window: window,
                              label: "按项目（范围）") else { return [] }
        var result: [HarnessProjectUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cwd = clipText(stmt, 0) else { continue }
            result.append(HarnessProjectUsage(
                path: cwd,
                displayName: HarnessProjectNaming.displayName(forPath: cwd),
                sessionCount: Int(sqlite3_column_int64(stmt, 1)),
                usage: usageRow(stmt, offset: 2)
            ))
        }
        return result
    }

    private func queryModels(_ db: OpaquePointer, sql: String,
                             window: HarnessMsWindow) -> [HarnessModelUsage] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard prepareWindowed(db, sql: sql, stmt: &stmt, window: window,
                              label: "按模型（范围）") else { return [] }
        var result: [HarnessModelUsage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HarnessModelUsage(
                provider: clipText(stmt, 0) ?? "",
                model: clipText(stmt, 1) ?? "",
                usage: usageRow(stmt, offset: 2)
            ))
        }
        return result
    }

    /// 统一准备 + 绑定窗口参数（两条 SQL 形状一致：两个占位符依次为 from / to）
    private func prepareWindowed(_ db: OpaquePointer, sql: String, stmt: inout OpaquePointer?,
                                 window: HarnessMsWindow, label: String) -> Bool {
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness \(label)聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return false
        }
        sqlite3_bind_int64(stmt, 1, window.fromMs)
        sqlite3_bind_int64(stmt, 2, window.toMs)
        return true
    }

    /// 从第 offset 列起读五项用量（顺序：未缓存 / 输出 / 缓存读 / 缓存写 / 请求数）
    private func usageRow(_ stmt: OpaquePointer?, offset: Int32) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: Int(sqlite3_column_int64(stmt, offset)),
            output: Int(sqlite3_column_int64(stmt, offset + 1)),
            cacheRead: Int(sqlite3_column_int64(stmt, offset + 2)),
            cacheWrite: Int(sqlite3_column_int64(stmt, offset + 3)),
            requestCount: Int(sqlite3_column_int64(stmt, offset + 4))
        )
    }
}
