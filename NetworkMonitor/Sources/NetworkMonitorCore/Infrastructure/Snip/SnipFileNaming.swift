import Foundation

// MARK: - 截图文件命名与目录

/// 截图落盘规则 — 文件名与快速保存目录都是纯函数，便于单测
public enum SnipFileNaming {

    /// 文件名形如 Snipaste_2026-10-24_19-05-30.png
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        "Snipaste_\(timestamp(for: date, calendar: calendar)).png"
    }

    /// 文件名中的时间戳部分
    public static func timestamp(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    /// 快速保存与自动保存共用的目录（~/Pictures/NetworkMonitor Snips）
    public static func quickSaveDirectory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("NetworkMonitor Snips", isDirectory: true)
    }
}
