import Foundation
import SQLite3

// MARK: - 按来源的项目 / 模型聚合（累计 + 三档窗口，一条查询各出一份）

/// 单来源视图要的排行数据
///
/// **性能口径（P0）**：累计口径与三档窗口原本是两条查询（每个维度 2 次全表扫描），
/// 合并成一条后每个维度只扫一次 —— 累计列不带 CASE（全表求和）、窗口列用 CASE 分桶，
/// 同一行数据只读一遍。窗口列构造复用 `windowColumns`，与全量视图口径同源。
extension DatabaseManager {

    /// 每来源的累计项目 / 模型 + 三档窗口（两条查询：项目一条、模型一条）
    func harnessSourceRankings(
        _ db: OpaquePointer,
        now: Date
    ) -> (
        projects: [TokenSourceID: [HarnessProjectUsage]],
        models: [TokenSourceID: [HarnessModelUsage]],
        windowed: [TokenSourceID: [HarnessUsageWindow: HarnessWindowedUsage]]
    ) {
        let windows = HarnessRangeWindows.allWindows(now: now)
        let projectRows = sourceProjectRows(db, windows: windows)
        let modelRows = sourceModelRows(db, windows: windows)

        var cumulativeProjects: [TokenSourceID: [HarnessProjectUsage]] = [:]
        var windowedProjects: [TokenSourceID: [HarnessUsageWindow: [HarnessProjectUsage]]] = [:]
        for (source, byKey) in projectRows {
            cumulativeProjects[source] = byKey[Self.cumulativeWindowKey]
            for (key, rows) in byKey where key != Self.cumulativeWindowKey {
                guard let window = HarnessUsageWindow(rawValue: key) else { continue }
                windowedProjects[source, default: [:]][window] = rows
            }
        }
        var cumulativeModels: [TokenSourceID: [HarnessModelUsage]] = [:]
        var windowedModels: [TokenSourceID: [HarnessUsageWindow: [HarnessModelUsage]]] = [:]
        for (source, byKey) in modelRows {
            cumulativeModels[source] = byKey[Self.cumulativeWindowKey]
            for (key, rows) in byKey where key != Self.cumulativeWindowKey {
                guard let window = HarnessUsageWindow(rawValue: key) else { continue }
                windowedModels[source, default: [:]][window] = rows
            }
        }

        var windowed: [TokenSourceID: [HarnessUsageWindow: HarnessWindowedUsage]] = [:]
        for source in Set(windowedProjects.keys).union(windowedModels.keys) {
            var byWindow: [HarnessUsageWindow: HarnessWindowedUsage] = [:]
            for entry in windows {
                let projects = Self.sortedProjects(windowedProjects[source]?[entry.window] ?? [])
                let models = Self.sortedModels(windowedModels[source]?[entry.window] ?? [])
                byWindow[entry.window] = HarnessWindowedUsage(
                    window: entry.window,
                    projects: projects,
                    models: models,
                    projectTotals: projects.reduce(HarnessTokenUsage()) { $0.adding($1.usage) },
                    modelTotals: models.reduce(HarnessTokenUsage()) { $0.adding($1.usage) }
                )
            }
            windowed[source] = byWindow
        }
        return (cumulativeProjects.mapValues(Self.sortedProjects),
                cumulativeModels.mapValues(Self.sortedModels),
                windowed)
    }

    /// 累计口径的「窗口」占位键（项目 / 模型行按它分流累计与窗口两组）
    ///
    /// 用一个不可能出现在 allCases 里的值做字典键，避免再拆两套返回结构；
    /// 读取侧只把 `!= cumulativeKey` 的行当窗口行。
    private static let cumulativeWindowKey = -1

    // MARK: - 项目

    /// 每来源 × (累计 | 三档窗口) 的项目行，一条查询出全部
    private func sourceProjectRows(
        _ db: OpaquePointer,
        windows: [(window: HarnessUsageWindow, range: HarnessMsWindow)]
    ) -> [TokenSourceID: [Int: [HarnessProjectUsage]]] {
        let windowColumns = Self.windowColumns(Int32(windows.count), withSessions: true)
        let sql = """
        SELECT source, cwd, COUNT(DISTINCT session_id),
               COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*),
               \(windowColumns)
        FROM harness_token_event
        WHERE cwd <> ''
        GROUP BY source, cwd;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            logger.warning("Harness 按来源项目聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        _ = Self.bindWindows(stmt, windows: windows, withSessions: true)
        var result: [TokenSourceID: [Int: [HarnessProjectUsage]]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = sourceID(stmt, 0), let cwd = clipText(stmt, 1) else { continue }
            let displayName = HarnessProjectNaming.displayName(forPath: cwd)
            // 列序：source(0) / cwd(1) + 累计 6 列（会话数、4 桶、请求数）+ 每窗口 6 列
            result[source, default: [:]][Self.cumulativeWindowKey, default: []].append(HarnessProjectUsage(
                path: cwd,
                displayName: displayName,
                sessionCount: Int(sqlite3_column_int64(stmt, 2)),
                usage: Self.usage(stmt, base: 3, requestCount: Int(sqlite3_column_int64(stmt, 7)))
            ))
            for (offset, entry) in windows.enumerated() {
                let base = Int32(8 + offset * 6)
                result[source, default: [:]][entry.window.rawValue, default: []].append(HarnessProjectUsage(
                    path: cwd,
                    displayName: displayName,
                    sessionCount: Int(sqlite3_column_int64(stmt, base + 5)),
                    usage: Self.usage(stmt, base: base,
                                      requestCount: Int(sqlite3_column_int64(stmt, base + 4)))
                ))
            }
        }
        return result
    }

    // MARK: - 模型

    /// 每来源 × (累计 | 三档窗口) 的模型行，一条查询出全部
    private func sourceModelRows(
        _ db: OpaquePointer,
        windows: [(window: HarnessUsageWindow, range: HarnessMsWindow)]
    ) -> [TokenSourceID: [Int: [HarnessModelUsage]]] {
        let windowColumns = Self.windowColumns(Int32(windows.count), withSessions: false)
        let sql = """
        SELECT source, provider, model,
               COALESCE(SUM(uncached_in), 0), COALESCE(SUM(output), 0),
               COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0), COUNT(*),
               \(windowColumns)
        FROM harness_token_event
        GROUP BY source, provider, model;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            logger.warning("Harness 按来源模型聚合准备失败: " + String(cString: sqlite3_errmsg(db)))
            return [:]
        }
        _ = Self.bindWindows(stmt, windows: windows, withSessions: false)
        var result: [TokenSourceID: [Int: [HarnessModelUsage]]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let source = sourceID(stmt, 0) else { continue }
            let provider = clipText(stmt, 1) ?? ""
            let model = clipText(stmt, 2) ?? ""
            // 列序：source(0) / provider(1) / model(2) + 累计 5 列（4 桶、请求数）+ 每窗口 5 列
            result[source, default: [:]][Self.cumulativeWindowKey, default: []].append(HarnessModelUsage(
                provider: provider,
                model: model,
                usage: Self.usage(stmt, base: 3, requestCount: Int(sqlite3_column_int64(stmt, 7)))
            ))
            for (offset, entry) in windows.enumerated() {
                let base = Int32(8 + offset * 5)
                result[source, default: [:]][entry.window.rawValue, default: []].append(HarnessModelUsage(
                    provider: provider,
                    model: model,
                    usage: Self.usage(stmt, base: base,
                                      requestCount: Int(sqlite3_column_int64(stmt, base + 4)))
                ))
            }
        }
        return result
    }

    // MARK: - 公共小工具

    /// 读取 source 列（未知 rawValue 视为损坏行，跳过）
    func sourceID(_ stmt: OpaquePointer, _ index: Int32) -> TokenSourceID? {
        guard let raw = clipText(stmt, index) else { return nil }
        return TokenSourceID(rawValue: raw)
    }

    /// 从「4 桶 + 请求数」列位置读一个用量值
    private static func usage(_ stmt: OpaquePointer, base: Int32, requestCount: Int) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: Int(sqlite3_column_int64(stmt, base)),
            output: Int(sqlite3_column_int64(stmt, base + 1)),
            cacheRead: Int(sqlite3_column_int64(stmt, base + 2)),
            cacheWrite: Int(sqlite3_column_int64(stmt, base + 3)),
            requestCount: requestCount
        )
    }

    /// 丢掉零用量行后按总 token 降序、并列按路径升序（与全量口径一致）
    static func sortedProjects(_ rows: [HarnessProjectUsage]) -> [HarnessProjectUsage] {
        rows.filter { !$0.usage.isZero }.sorted { lhs, rhs in
            lhs.usage.totalTokens == rhs.usage.totalTokens
                ? lhs.path < rhs.path
                : lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }

    /// 丢掉零用量行后按总 token 降序、并列按模型名升序
    static func sortedModels(_ rows: [HarnessModelUsage]) -> [HarnessModelUsage] {
        rows.filter { !$0.usage.isZero }.sorted { lhs, rhs in
            lhs.usage.totalTokens == rhs.usage.totalTokens
                ? lhs.model < rhs.model
                : lhs.usage.totalTokens > rhs.usage.totalTokens
        }
    }
}
