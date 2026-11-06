import Foundation
import SQLite3

// MARK: - 按范围聚合（项目 / 模型）

/// 按范围的项目与模型聚合 —— 与累计口径各算一份，页面只取当前范围那份
///
/// **性能实测（本机真实索引库 monitor.db / 133k 行，见交接文档）**：
/// - 三档逐条查（今日 46ms + 近 7 天 80ms + 近 30 天 198ms）≈ 324ms/两表，切范围还要再查一次
/// - **单条 CASE WHEN 分窗口（本文件采用的写法）**：项目 82ms + 模型 104ms ≈ 186ms，
///   与改造前的两条累计查询（178~250ms）基本持平，换来「切范围零查询 + 与 Hero 同口径」
/// - 结论：三档一次算完并随快照缓存（惰性查会让切范围多一次 40~200ms 往返且要处理异步）
///
/// 窗口嵌套（30 ⊃ 7 ⊃ 今日）因此可以让每条 SQL 只扫一遍事件表，用 CASE WHEN 把同一行
/// 同时计入多个窗口，避免三倍扫描。
extension DatabaseManager {

    /// 三档窗口的项目 / 模型聚合（顺序同 `HarnessUsageWindow.allCases`）
    func harnessWindowedUsage(_ db: OpaquePointer, now: Date) -> [HarnessWindowedUsage] {
        let windows = HarnessRangeWindows.allWindows(now: now)
        let projectTable = mergedProjects(db, windows: windows)
        let modelTable = mergedModels(db, windows: windows)
        return windows.map { entry in
            // 这里拿到的是**未裁剪**的全部行：分母用它们求和（含 TopN 之外，
            // 但已排除 cwd 为空 / 无法归属项目的事件，所以 sum(占比) ≤ 100% 且不虚高）
            let projects = sortedProjects(projectTable[entry.window] ?? [])
            let models = sortedModels(modelTable[entry.window] ?? [])
            return HarnessWindowedUsage(
                window: entry.window,
                projects: projects,
                models: models,
                projectTotals: projects.reduce(HarnessTokenUsage()) { $0.adding($1.usage) },
                modelTotals: models.reduce(HarnessTokenUsage()) { $0.adding($1.usage) }
            )
        }
    }

    // MARK: - SQL（单条扫一遍，CASE WHEN 分窗口）

    /// 每窗口选择列（顺序：未缓存 / 输出 / 缓存读 / 缓存写 / 请求数 + 可选会话去重）
    ///
    /// 请求数用 `SUM(... THEN 1 ELSE 0 END)` 而不是 `COUNT(*)`：
    /// 聚合函数不能嵌在 `SUM(CASE ...)` 里（SQLite 会报 "misuse of aggregate function COUNT()"）。
    private static func windowColumns(_ count: Int32, withSessions: Bool) -> String {
        let fields = ["uncached_in", "output", "cache_read", "cache_write"]
        var parts: [String] = []
        for _ in 0..<count {
            for field in fields {
                parts.append("COALESCE(SUM(CASE WHEN ts_ms >= ? AND ts_ms < ? THEN \(field) ELSE 0 END), 0)")
            }
            parts.append("COALESCE(SUM(CASE WHEN ts_ms >= ? AND ts_ms < ? THEN 1 ELSE 0 END), 0)")
            if withSessions {
                parts.append("COUNT(DISTINCT CASE WHEN ts_ms >= ? AND ts_ms < ? THEN session_id END)")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// 绑定按 SELECT 项出现顺序排列的窗口参数（每个窗口 6 组「from / to」× 窗口数）
    private static func bindWindows(_ stmt: OpaquePointer,
                                    windows: [(window: HarnessUsageWindow, range: HarnessMsWindow)],
                                    withSessions: Bool) -> Int32 {
        var index: Int32 = 1
        for entry in windows {
            let repeats = withSessions ? 6 : 5
            for _ in 0..<repeats {
                sqlite3_bind_int64(stmt, index, entry.range.fromMs)
                sqlite3_bind_int64(stmt, index + 1, entry.range.toMs)
                index += 2
            }
        }
        return index
    }

    /// 项目三档合并查询（cwd 为空的事件不归属任何项目）
    private func mergedProjects(_ db: OpaquePointer,
                                windows: [(window: HarnessUsageWindow, range: HarnessMsWindow)])
        -> [HarnessUsageWindow: [HarnessProjectUsage]] {
        let columns = Self.windowColumns(Int32(windows.count), withSessions: true)
        let sql = """
        SELECT cwd, \(columns)
        FROM harness_token_event
        WHERE cwd <> ''
        GROUP BY cwd;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 项目窗口聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        guard let stmt else { return [:] }
        _ = Self.bindWindows(stmt, windows: windows, withSessions: true)
        var result: [HarnessUsageWindow: [HarnessProjectUsage]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cwd = clipText(stmt, 0) else { continue }
            for (offset, entry) in windows.enumerated() {
                let base = Int32(1 + offset * 6)
                result[entry.window, default: []].append(HarnessProjectUsage(
                    path: cwd,
                    displayName: HarnessProjectNaming.displayName(forPath: cwd),
                    sessionCount: Int(sqlite3_column_int64(stmt, base + 5)),
                    usage: HarnessTokenUsage(
                        uncachedInput: Int(sqlite3_column_int64(stmt, base)),
                        output: Int(sqlite3_column_int64(stmt, base + 1)),
                        cacheRead: Int(sqlite3_column_int64(stmt, base + 2)),
                        cacheWrite: Int(sqlite3_column_int64(stmt, base + 3)),
                        requestCount: Int(sqlite3_column_int64(stmt, base + 4))
                    )))
            }
        }
        return result
    }

    /// 模型三档合并查询
    private func mergedModels(_ db: OpaquePointer,
                              windows: [(window: HarnessUsageWindow, range: HarnessMsWindow)])
        -> [HarnessUsageWindow: [HarnessModelUsage]] {
        let columns = Self.windowColumns(Int32(windows.count), withSessions: false)
        let sql = """
        SELECT provider, model, \(columns)
        FROM harness_token_event
        GROUP BY provider, model;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("Harness 模型窗口聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        guard let stmt else { return [:] }
        _ = Self.bindWindows(stmt, windows: windows, withSessions: false)
        var result: [HarnessUsageWindow: [HarnessModelUsage]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            for (offset, entry) in windows.enumerated() {
                let base = Int32(2 + offset * 5)
                result[entry.window, default: []].append(HarnessModelUsage(
                    provider: clipText(stmt, 0) ?? "",
                    model: clipText(stmt, 1) ?? "",
                    usage: HarnessTokenUsage(
                        uncachedInput: Int(sqlite3_column_int64(stmt, base)),
                        output: Int(sqlite3_column_int64(stmt, base + 1)),
                        cacheRead: Int(sqlite3_column_int64(stmt, base + 2)),
                        cacheWrite: Int(sqlite3_column_int64(stmt, base + 3)),
                        requestCount: Int(sqlite3_column_int64(stmt, base + 4))
                    )))
            }
        }
        return result
    }

    // MARK: - 排序

    /// 按总 token 降序、并列按路径升序（与累计口径的 ORDER BY 一致）
    ///
    /// 先丢掉该窗口内零用量的行：CASE WHEN 会把「本窗口没有事件、别的窗口有」的项目
    /// 也算出一行全 0，旧实现靠 WHERE ts_ms 过滤天然不会出现这种行。
    private func sortedProjects(_ rows: [HarnessProjectUsage]) -> [HarnessProjectUsage] {
        rows.filter { !$0.usage.isZero }.sorted { lhs, rhs in
            lhs.usage.totalTokens == rhs.usage.totalTokens
                ? lhs.path < rhs.path
                : lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }

    /// 按总 token 降序、并列按模型名升序（同样丢掉本窗口零用量的行）
    private func sortedModels(_ rows: [HarnessModelUsage]) -> [HarnessModelUsage] {
        rows.filter { !$0.usage.isZero }.sorted { lhs, rhs in
            lhs.usage.totalTokens == rhs.usage.totalTokens
                ? lhs.model < rhs.model
                : lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }
}
