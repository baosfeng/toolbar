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

    // 输出格式：默认 PNG；JPEG 只换扩展名，时间戳规则不动
    assertEqual(SnipFileNaming.fileName(for: date, format: .jpeg, calendar: calendar).hasSuffix(".jpg"),
                true, "JPEG 文件名以 jpg 结尾")
    assertEqual(SnipFileNaming.fileName(for: date, format: .png, calendar: calendar),
                SnipFileNaming.fileName(for: date, calendar: calendar),
                "显式 PNG 与默认口径一致（老调用点不受影响）")
    assertEqual(SnipImageFormat.resolved(raw: nil), SnipImageFormat.png, "缺失格式偏好落到 PNG")
    assertEqual(SnipImageFormat.resolved(raw: "gif"), SnipImageFormat.png, "未知格式落到 PNG")
    assertEqual(SnipImageFormat.resolved(raw: "jpeg"), SnipImageFormat.jpeg, "jpeg 能解析")
    assertEqual(SnipImageFormat.jpeg.fileExtension, "jpg", "JPEG 扩展名统一写 jpg")
    assertEqual(SnipImageFormat.jpeg.displayName, "JPEG", "格式显示名")
    assertEqual(SnipImageFormat.clampedQuality(1.8), SnipImageFormat.jpegQualityRange.upperBound,
                "质量上限夹紧")
    assertEqual(SnipImageFormat.clampedQuality(0.01), SnipImageFormat.jpegQualityRange.lowerBound,
                "质量下限夹紧")
    assertEqual(SnipImageFormat.clampedQuality(0.75), 0.75, "区间内质量原样保留")
    assertEqual(SnipImageFormat.clampedQuality(Double.nan), SnipImageFormat.defaultJPEGQuality,
                "非法质量回落默认 0.9")

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
