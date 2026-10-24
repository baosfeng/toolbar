import Foundation
import NetworkMonitorCore

// MARK: - 截图文件命名与上次选区编码

func runSnipFileTests() {
    print("🧪 Testing Snip file naming & selection coding...")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    let date = Date(timeIntervalSince1970: 1_767_000_000)
    let stamp = SnipFileNaming.timestamp(for: date, calendar: calendar)
    assertEqual(stamp.count, 19, "时间戳固定 19 个字符")
    assertEqual(stamp.contains("_"), true, "日期与时间用下划线分隔")
    assertEqual(SnipFileNaming.fileName(for: date, calendar: calendar).hasSuffix(".png"), true, "文件名以 png 结尾")
    assertEqual(SnipFileNaming.fileName(for: date, calendar: calendar).hasPrefix("Snipaste_"), true, "文件名前缀固定")

    let home = URL(fileURLWithPath: "/Users/tester")
    assertEqual(SnipFileNaming.quickSaveDirectory(homeDirectory: home).path,
                "/Users/tester/Pictures/NetworkMonitor Snips", "快速保存目录")

    // 上次选区编码
    let rect = CGRect(x: 12.5, y: -30, width: 400, height: 300)
    let encoded = SnipSelectionCoding.encode(rect)
    assertEqual(SnipSelectionCoding.decode(encoded), rect, "编码解码往返一致")
    assertEqual(SnipSelectionCoding.decode(nil) == nil, true, "空值返回 nil")
    assertEqual(SnipSelectionCoding.decode("1,2,3") == nil, true, "字段不足返回 nil")
    assertEqual(SnipSelectionCoding.decode("0,0,0,100") == nil, true, "零宽返回 nil")
    assertEqual(SnipSelectionCoding.decode("abc") == nil, true, "非数字返回 nil")
    assertEqual(SnipSelectionCoding.decode(" 1 , 2 , 30 , 40 "), CGRect(x: 1, y: 2, width: 30, height: 40), "容忍空格")
}
