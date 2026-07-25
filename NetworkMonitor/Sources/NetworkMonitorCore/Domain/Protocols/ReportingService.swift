import Foundation

// MARK: - 报告生成服务

/// 报告生成服务
public protocol ReportingService: AnyObject, Sendable {
    /// 报告目录路径
    var reportsDirectoryPath: String { get }

    /// 生成今日报告
    @discardableResult
    func generateDailyReport() -> String?

    /// 生成昨日报告
    @discardableResult
    func generateYesterdayReport() -> String?

    /// 生成上周报告
    @discardableResult
    func generateWeeklyReport() -> String?
}
