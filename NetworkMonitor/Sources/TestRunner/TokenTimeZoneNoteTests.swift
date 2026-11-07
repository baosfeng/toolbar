import Foundation
import NetworkMonitorCore

// MARK: - Token 时间口径的界面说明

/// 口径说明必须存在且写明时区，否则用户改系统时区后会把「今日」当成统计错误
func runTokenTimeZoneNoteTests() {
    print("🧪 Testing Token 时间口径说明...")

    // 数据层口径：固定 Asia/Shanghai
    assertEqual(HarnessTokenTimeWindow.timeZoneIdentifier, "Asia/Shanghai", "数据层口径固定上海时区")

    // 界面说明必须点出时区与「不跟随系统」两件事
    let note = TokenTimeZoneNote.text
    assertEqual(note.contains("Asia/Shanghai"), true, "说明里点名时区")
    assertEqual(note.contains("不跟随系统时区"), true, "说明里点明不跟随系统")

    // 时区确实不是系统时区时才需要说明：若将来改成跟随系统，这条会提醒同步改文案
    let systemZone = TimeZone.current.identifier
    if systemZone != HarnessTokenTimeWindow.timeZoneIdentifier {
        assertEqual(note.isEmpty, false, "与系统时区不同时说明不能为空")
    }

    // 边界仍然按上海切：UTC 16:30 归上海次日（用真实时间戳，别手算时间戳常量）
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let utc1630 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20,
                                                     hour: 16, minute: 30))!
    let tsMs = Int64((utc1630.timeIntervalSince1970 * 1000).rounded())
    assertEqual(HarnessTokenTimeWindow.dayKey(tsMs: tsMs), "2026-10-21", "UTC 16:30 归上海次日")

    print("✅ Token 时间口径说明 works")
}
