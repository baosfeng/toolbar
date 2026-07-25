import Foundation

/// 报告生成器：生成每日/每周 Markdown 格式统计报告
public final class ReportGenerator: ReportingService {

    private let database: DatabaseManager
    private let statsProvider: StatsProvider

    private var reportsDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("macMonitor/reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public init(database: DatabaseManager, statsProvider: StatsProvider) {
        self.database = database
        self.statsProvider = statsProvider
    }

    /// 报告目录路径
    public var reportsDirectoryPath: String {
        reportsDir.path
    }

    // MARK: - 生成每日报告

    /// 生成今日报告
    @discardableResult
    public func generateDailyReport() -> String? {
        let stats = statsProvider.fetchTodayStats()
        let dateStr = dateString()
        let content = buildDailyReport(date: dateStr, stats: stats)

        let fileURL = reportsDir.appendingPathComponent("\(dateStr).md")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📝 今日报告已生成: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("⚠️ 报告写入失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 生成昨日报告
    @discardableResult
    public func generateYesterdayReport() -> String? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let dateStr = dateString(for: yesterday)

        let stats = statsProvider.fetchTodayStats()
        let content = buildDailyReport(date: dateStr, stats: stats)

        let fileURL = reportsDir.appendingPathComponent("\(dateStr).md")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📝 昨日报告已生成: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("⚠️ 报告写入失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 生成每周报告

    /// 生成上周报告
    @discardableResult
    public func generateWeeklyReport() -> String? {
        let weekStr = weekString()
        let content = buildWeeklyReport(week: weekStr)

        let fileURL = reportsDir.appendingPathComponent("\(weekStr).md")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            print("📝 每周报告已生成: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("⚠️ 报告写入失败: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 构建报告内容

    private func buildDailyReport(date: String, stats: TodayStats) -> String {
        var md = "# 每日活动报告 — \(date)\n\n"
        md += "> 自动生成于 \(timeString())\n\n"

        md += "## 📊 今日概览\n\n"
        md += "| 指标 | 数值 |\n"
        md += "|------|------|\n"
        md += "| ⏱ 活跃时间 | \(formatDuration(stats.activeSeconds)) |\n"
        md += "| ⌨️ 击键次数 | \(formatNumber(stats.keyPressCount)) |\n"
        md += "| 💡 亮屏时长 | \(formatDuration(stats.screenOnSeconds)) |\n"
        md += "| 🌙 息屏时长 | \(formatDuration(stats.screenOffSeconds)) |\n"
        md += "| 💻 内存使用 | \(stats.memoryUsedMB) MB / \(stats.memoryTotalMB) MB |\n"
        md += "| 📈 CPU 使用率 | \(String(format: "%.1f", stats.cpuUsage))% |\n\n"

        if !stats.appRanking.isEmpty {
            md += "## 🏆 最活跃软件\n\n"
            md += "| 排名 | 应用 | 使用时长 |\n"
            md += "|------|------|---------|\n"
            for (index, app) in stats.appRanking.enumerated() {
                md += "| \(index + 1) | \(app.name) | \(formatDuration(app.duration)) |\n"
            }
            md += "\n"
        }

        md += "## 💻 资源占用\n\n"
        md += "- CPU: \(String(format: "%.1f", stats.cpuUsage))%\n"
        md += "- 内存: \(stats.memoryUsedMB) MB / \(stats.memoryTotalMB) MB\n"
        md += "- 下载: \(formatBytes(stats.netDownloadSpeed))/s\n"
        md += "- 上传: \(formatBytes(stats.netUploadSpeed))/s\n"

        md += "\n---\n"
        md += "*macMonitor — 数据仅存本地，不上传网络*\n"

        return md
    }

    private func buildWeeklyReport(week: String) -> String {
        var md = "# 每周活动报告 — \(week)\n\n"
        md += "> 自动生成于 \(timeString())\n\n"

        md += "## 📈 本周概览\n\n"
        md += "本周详细数据请查看每日报告。\n\n"
        md += "| 日期 | 报告 |\n"
        md += "|------|------|\n"

        let today = Date()
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        for dayOffset in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) {
                let dayStr = dateString(for: day)
                md += "| \(dayStr) | [查看报告](./\(dayStr).md) |\n"
            }
        }

        md += "\n---\n"
        md += "*macMonitor — 数据仅存本地，不上传网络*\n"

        return md
    }

    // MARK: - 辅助

    private func dateString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }

    private func weekString() -> String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        return "\(year)-W\(String(format: "%02d", weekOfYear))"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours) 小时 \(minutes) 分钟"
        }
        return "\(minutes) 分钟"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024)KB" }
        return String(format: "%.1fMB", Double(bytes) / 1024.0 / 1024.0)
    }
}
