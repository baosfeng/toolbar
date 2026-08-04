import Foundation

// MARK: - stats JSONL 导入器

/// 将 reasonix 官方 stats JSONL（`~/.reasonix/stats/YYYY-MM-DD.jsonl`）增量导入数据库 `token_usage` 表。
///
/// 设计要点：
/// - **幂等**：`token_usage` 表有 `UNIQUE(source, date, ts, model, total_tokens)`，
///   使用 `INSERT OR IGNORE`，重复导入同一行不会产生重复记录，因此全量扫描即可实现增量同步。
/// - **节流**：hook 事件触发频繁，`syncIfNeeded()` 保证两次真正扫描之间至少间隔
///   `minSyncInterval`（默认 3 秒），避免每次事件都扫盘。
/// - **容错**：torn line（崩溃残留的半行）由 `ReasonixStatsRecord.parseLine` 跳过，
///   单文件解析失败不影响其他文件。
///
/// 未来扩展：`source` 参数预留了多软件接入（claude/codex 的会话 jsonl 导入时传各自 source）。
public final class StatsImporter: @unchecked Sendable {

    private let database: DatabaseService
    private let statsDir: String
    private let queue = DispatchQueue(label: "com.example.NetworkMonitor.stats-importer")
    private var lastSyncAt = Date.distantPast
    private let minSyncInterval: TimeInterval

    /// 创建导入器
    /// - Parameters:
    ///   - database: 数据库服务（协议注入，测试可用内存库）
    ///   - statsDir: stats 目录，默认 `~/.reasonix/stats`
    ///   - minSyncInterval: 最小同步间隔（秒），默认 3 秒
    public init(database: DatabaseService, statsDir: String? = nil, minSyncInterval: TimeInterval = 3.0) {
        self.database = database
        self.statsDir = statsDir ?? ReasonixStatsLoader.defaultStatsDir()
        self.minSyncInterval = minSyncInterval
    }

    /// 全量同步一次（不受节流限制）。应用启动时调用，兜底保证最新数据已导入。
    public func syncAll() {
        queue.async { [self] in
            self.importAll()
            self.lastSyncAt = Date()
        }
    }

    /// 节流同步：距离上次扫描不足 `minSyncInterval` 则跳过。
    /// hook 每次事件触发时调用。
    public func syncIfNeeded() {
        queue.async { [self] in
            let now = Date()
            guard now.timeIntervalSince(self.lastSyncAt) >= self.minSyncInterval else { return }
            self.importAll()
            self.lastSyncAt = now
        }
    }

    // MARK: - 内部实现

    private func importAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: statsDir) else { return }

        // 按文件名排序，保证导入顺序稳定
        let jsonlFiles = files
            .filter { $0.hasSuffix(".jsonl") }
            .sorted()

        for filename in jsonlFiles {
            // 文件名即本地日期：YYYY-MM-DD.jsonl
            let date = String(filename.dropLast(".jsonl".count))
            guard date.count == 10 else { continue }

            let path = (statsDir as NSString).appendingPathComponent(filename)
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            var imported = 0
            for line in content.split(separator: "\n") {
                guard let record = ReasonixStatsLoader.parseLine(String(line), date: date) else { continue }
                let hour = localHour(from: record.ts)
                database.insertTokenUsage(source: "reasonix", date: date, hour: hour, record: record)
                imported += 1
            }
            if imported > 0 {
                print("📥 stats 导入 \(filename): \(imported) 条记录")
            }
        }
    }

    /// 从 ISO8601 时间戳（自带时区）解析本地小时 0-23；解析失败返回 -1
    private func localHour(from ts: String) -> Int {
        guard let date = ReasonixStatsLoader.parseTimestamp(ts) else { return -1 }
        return Calendar.current.component(.hour, from: date)
    }
}
