import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - Assertion Helpers

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual == expected {
        print("✅ \(expected)", message.isEmpty ? "" : " — \(message)")
    } else {
        print("❌ \(file):\(line) — expected \"\(expected)\", got \"\(actual)\"\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

func assertNotNil<T>(_ value: T?, _ message: String = "", file: String = #file, line: Int = #line) {
    if value != nil {
        print("✅ \(message.isEmpty ? "not nil" : message)")
    } else {
        print("❌ \(file):\(line) — expected not nil\(message.isEmpty ? "" : " — \(message)")")
        exit(1)
    }
}

// MARK: - Test formatSpeedShort

let speedCases: [(bps: Double, expected: String)] = [
    (0.0, "0B"),
    (500.0, "500B"),
    (1_500.0, "2K"),
    (42_000.0, "42K"),
    (999_000.0, "999K"),
    (1_200_000.0, "1.2M"),
    (55_000_000.0, "55.0M"),
    (2_300_000_000.0, "2.3G"),
]
print("🧪 Testing formatSpeedShort...")
for (bps, expected) in speedCases {
    assertEqual(formatSpeedShort(bps), expected)
}

// MARK: - Test parseNettopLine

print("\n🧪 Testing parseNettopLine...")

let line1 = "23:46:47.674162 Google Chrome H.51129                                   16218            4096"
let r1 = parseNettopLine(line1)
assertNotNil(r1, "should parse normal line")
if let r = r1 {
    assertEqual(r.name, "Google Chrome H", "name")
    assertEqual(r.pid, Int32(51129), "pid")
    assertEqual(r.bytesIn, UInt64(16218), "bytesIn")
    assertEqual(r.bytesOut, UInt64(4096), "bytesOut")
}

let lineMulti = "23:46:48.123456 Microsoft Excel T.12345                                   98765           43210"
let rMulti = parseNettopLine(lineMulti)
assertNotNil(rMulti, "multi-word name")
if let r = rMulti {
    assertEqual(r.name, "Microsoft Excel T", "multi-word name")
    assertEqual(r.pid, Int32(12345), "multi-word pid")
    assertEqual(r.bytesIn, UInt64(98765), "multi-word bytesIn")
}

let line2 = "23:46:47.674152 airportd.649                                                                                   0               0"
let r2 = parseNettopLine(line2)
assertNotNil(r2, "should parse zero line")
if let r = r2 {
    assertEqual(r.name, "airportd")
    assertEqual(r.bytesIn, UInt64(0))
}

let line3 = "23:46:47.674157 mDNSResponder.689                                                                  105434952       59651139"
let r3 = parseNettopLine(line3)
assertNotNil(r3, "should parse large numbers")
if let r = r3 {
    assertEqual(r.bytesIn, UInt64(105434952))
    assertEqual(r.bytesOut, UInt64(59651139))
}

let header = parseNettopLine("time                                                                            interface   type        bytes_in       bytes_out   rcvsize  tc_class arch")
assertEqual(header, nil, "header should return nil")

let empty = parseNettopLine("")
assertEqual(empty, nil, "empty should return nil")

// MARK: - Test sparkline

print("\n🧪 Testing sparkline...")

assertEqual(sparkline(from: []), "", "empty")

let allSame = sparkline(from: [0, 0, 0])
assertEqual(allSame, "▁▁▁", "all zero")

let linear = sparkline(from: [0, 1, 2, 3, 4, 5, 6, 7])
assertEqual(linear, "▁▂▃▄▅▆▇█", "linear 0-7")

let single = sparkline(from: [42])
assertEqual(single, "█", "single peak")

let desc = sparkline(from: [5, 4, 3, 2, 1, 0])
assertEqual(desc, "█▆▅▃▂▁", "descending")

// MARK: - Test formatBytesFull

print("\n🧪 Testing formatBytesFull...")
assertEqual(formatBytesFull(0), "0 KB", "0 字节显示 0 KB（不再出现 Zero KB）")
assertEqual(formatBytesFull(1024), "1 KB")
assertEqual(formatBytesFull(1_000_000), "1 MB")
assertEqual(formatBytesFull(2_500_000_000), "2.5 GB")

// MARK: - Test TrafficTracker（每日流量追踪）

print("\n🧪 Testing TrafficTracker...")

do {
    // 模拟网络监控（累计值可变）
    final class MockMonitor: NetworkMonitoringService {
        var downloadSpeed: Double = 0
        var uploadSpeed: Double = 0
        var totalRx: UInt64
        var totalTx: UInt64

        init(totalRx: UInt64, totalTx: UInt64) {
            self.totalRx = totalRx
            self.totalTx = totalTx
        }

        func poll() {}
    }

    let suite = UserDefaults(suiteName: "test.traffic-\(UUID().uuidString)")!
    let monitor = MockMonitor(totalRx: 1000, totalTx: 500)
    let tracker = TrafficTracker(
        monitor: monitor,
        storage: UserDefaultsStorage(defaults: suite)
    )

    // 启动基准入库：累计值未变 → 今日流量 0
    assertEqual(tracker.todayRx, 0, "initial todayRx zero")
    assertEqual(tracker.todayTx, 0, "initial todayTx zero")

    // 累计增加 2.5MB / 1MB → 今日流量等于增量
    monitor.totalRx = 1_000 + 2_500_000
    monitor.totalTx = 500 + 1_000_000
    assertEqual(tracker.todayRx, 2_500_000, "todayRx equals increment")
    assertEqual(tracker.todayTx, 1_000_000, "todayTx equals increment")

    // weekEntries：无日志时仅今天一条，label 为短日期格式
    let entries = tracker.weekEntries
    assertEqual(entries.count, 1, "weekEntries only today without log")
    assertEqual(entries[0].rx, 2_500_000, "weekEntries today rx")
    assertEqual(entries[0].label.contains("/"), true, "week label short format")

    // 当天 update() 不切换日期、无副作用
    tracker.update()
    assertEqual(tracker.todayRx, 2_500_000, "update keeps today rx")

    // 基准解析：累计回退（崩溃重启读到更旧值）时以当前累计重建，正常增长时沿用
    assertEqual(TrafficTracker.resolveBaseline(currentRx: 100, currentTx: 50,
                                               storedRx: 1_000, storedTx: 500).rx, 100,
                "baseline resets on rx regression")
    assertEqual(TrafficTracker.resolveBaseline(currentRx: 1_000, currentTx: 50,
                                               storedRx: 1_000, storedTx: 500).tx, 50,
                "baseline resets on tx regression")
    let kept = TrafficTracker.resolveBaseline(currentRx: 2_000, currentTx: 900,
                                              storedRx: 1_000, storedTx: 500)
    assertEqual(kept.rx, 1_000, "baseline kept on rx growth")
    assertEqual(kept.tx, 500, "baseline kept on tx growth")

    // 端到端：存储基准大于当前累计 → 重建基准并落盘，之后增量恢复可见
    let suiteRegress = UserDefaults(suiteName: "test.traffic-regress-\(UUID().uuidString)")!
    let storageRegress = UserDefaultsStorage(defaults: suiteRegress)
    storageRegress.set(5_000, forKey: "dayStartRx")
    storageRegress.set(3_000, forKey: "dayStartTx")
    let monitorRegress = MockMonitor(totalRx: 1_000, totalTx: 500)
    let trackerRegress = TrafficTracker(monitor: monitorRegress, storage: storageRegress)
    assertEqual(trackerRegress.todayRx, 0, "regressed baseline shows zero today")
    assertEqual(storageRegress.integer(forKey: "dayStartRx"), 1_000,
                "regressed baseline persisted")
    monitorRegress.totalRx = 1_500
    assertEqual(trackerRegress.todayRx, 500, "today rx counts after regression reset")

    print("✅ TrafficTracker 每日流量 works")
}

// MARK: - Test DatabaseManager (in-memory)

print("\n🧪 Testing DatabaseManager...")

// Helper: run query on DatabaseManager and collect results as rows of [String?]
func collectQuery(_ db: DatabaseManager, sql: String) -> [[String?]] {
    var rows: [[String?]] = []
    db.query(sql: sql) { stmt in
        var row: [String?] = []
        let colCount = sqlite3_column_count(stmt)
        for i in 0..<colCount {
            if sqlite3_column_type(stmt, i) == SQLITE_NULL {
                row.append(nil)
            } else if let cStr = sqlite3_column_text(stmt, i) {
                row.append(String(cString: cStr))
            } else {
                row.append(nil)
            }
        }
        rows.append(row)
    }
    return rows
}

// Test: 时区与货币配置
do {
    let offset = SqliteTimeZone.offsetModifier
    assertEqual(offset.hasSuffix(" hours"), true, "offset should be 'N hours' format, got: \(offset)")

    // 汇率默认 7.2，可通过注入的 KeyValueStorage 覆盖（不污染 UserDefaults.standard）
    let currencyStorage = UserDefaultsStorage(defaults: UserDefaults(suiteName: "test.currency")!)
    CurrencyConfig.shared.storageOverride = currencyStorage
    currencyStorage.removeObject(forKey: CurrencyConfig.rateOverrideKey)
    assertEqual(CurrencyConfig.shared.usdToCnyRate, 7.2, "default rate 7.2")
    assertEqual(CurrencyConfig.shared.usdToCny(1.0), 7.2, "usdToCny conversion")
    currencyStorage.set(6.5, forKey: CurrencyConfig.rateOverrideKey)
    assertEqual(CurrencyConfig.shared.usdToCnyRate, 6.5, "override rate 6.5")
    assertEqual(CurrencyConfig.shared.usdToCny(1.0), 6.5, "usdToCny conversion with override")
    CurrencyConfig.shared.storageOverride = nil

    print("✅ 时区与货币配置 works")
}

// MARK: - Test AppEvents（应用事件总线）

do {
    var received = false
    let observer = NotificationCenter.default.addObserver(
        forName: AppEvents.clipboardChanged,
        object: nil,
        queue: nil
    ) { _ in
        received = true
    }
    AppEvents.postClipboardChanged()
    NotificationCenter.default.removeObserver(observer)
    assertEqual(received, true, "clipboardChanged 事件已发布并接收")

    print("✅ AppEvents 事件总线 works")
}

// MARK: - Test Clipboard 哈希 / 忽略判定 / 摘要

print("🧪 Testing Clipboard hash & ignore policy...")
do {
    // 忽略判定：系统三类标记 + 自激标记 + 黑名单
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["public.utf8-plain-text"], bundleID: "com.apple.Safari"), nil, "普通文本不忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["org.nspasteboard.ConcealedType"], bundleID: nil), ClipboardIgnoreReason.concealed, "保密类型被忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["org.nspasteboard.TransientType"], bundleID: nil), ClipboardIgnoreReason.transient, "瞬时类型被忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["org.nspasteboard.AutoGeneratedType"], bundleID: nil), ClipboardIgnoreReason.autoGenerated, "自动生成类型被忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["com.bsfeng.macmonitor.clipboard.internal"], bundleID: nil), ClipboardIgnoreReason.internalMarker, "自激标记被忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: ["public.utf8-plain-text"], bundleID: "com.evil.app", blacklistedBundleIDs: ["com.evil.app"]), ClipboardIgnoreReason.blacklistedApp, "黑名单应用被忽略")
    assertEqual(ClipboardIgnorePolicy.ignoreReason(typeNames: [], bundleID: nil), nil, "类型列表为空不忽略")
    assertEqual(ClipboardIgnorePolicy.isIgnoredTypeName(ClipboardPasteboardType.transient), true, "忽略标记类型识别")
    assertEqual(ClipboardIgnorePolicy.isIgnoredTypeName("public.utf8-plain-text"), false, "普通类型不识别为忽略")

    // 文本规范化：换行统一 + 去首尾空白 → 同哈希
    assertEqual(ClipboardContentHasher.normalizeText("a\r\nb"), "a\nb", "CRLF 统一为 LF")
    assertEqual(ClipboardContentHasher.normalizeText("   "), nil, "纯空白归一化为 nil")
    assertEqual(ClipboardContentHasher.hash(text: ""), nil, "空文本无哈希")
    assertEqual(ClipboardContentHasher.hash(text: "  \n\t "), nil, "空白文本无哈希")
    assertEqual(ClipboardContentHasher.hash(text: "hello\r\nworld  "), ClipboardContentHasher.hash(text: "hello\nworld"), "换行与首尾空白不影响哈希")
    assertEqual(ClipboardContentHasher.hash(text: "a") == ClipboardContentHasher.hash(text: "b"), false, "不同内容哈希不同")
    assertEqual(ClipboardContentHasher.sha256Hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "空字节 SHA256 已知向量")

    // 超长文本：截断落库但哈希取完整内容
    let huge = String(repeating: "中", count: 100)
    let payload = ClipboardContentHasher.prepareText(huge, maxBytes: 30)
    assertNotNil(payload, "超长文本产出载荷")
    if let payload {
        assertEqual(payload.isTruncated, true, "超长文本标记截断")
        assertEqual(payload.text.utf8.count <= 30, true, "截断后不超过上限")
        assertEqual(payload.contentHash, ClipboardContentHasher.hash(text: huge), "哈希取完整规范化文本")
    }
    assertEqual(ClipboardContentHasher.prepareText("hi")?.isTruncated, false, "短文本不截断")
    assertEqual(ClipboardContentHasher.truncate("中文abc", toUTF8Bytes: 4), "中", "按 UTF-8 边界截断不切裂多字节")
    assertEqual(ClipboardContentHasher.truncate("abc", toUTF8Bytes: 0), "", "上限为 0 返回空串")

    // 图片：空数据与超大图跳过
    assertEqual(ClipboardContentHasher.prepareImageData(Data()), nil, "空图片数据跳过")
    assertEqual(ClipboardContentHasher.prepareImageData(Data(count: 10), maxBytes: 5), nil, "超大图片跳过")
    assertNotNil(ClipboardContentHasher.prepareImageData(Data(count: 10), maxBytes: 10), "未超限图片产出哈希")
    assertEqual(ClipboardContentHasher.prepareImageData(Data([1, 2, 3])), ClipboardContentHasher.prepareImageData(Data([1, 2, 3])), "同字节同哈希")

    // 摘要：折叠换行 + 尾部截断
    assertEqual(ClipboardPreview.make(from: "line1\nline2"), "line1 line2", "换行折叠为空格")
    assertEqual(ClipboardPreview.make(from: "  a\t\tb  "), "a b", "连续空白折叠并去首尾")
    assertEqual(ClipboardPreview.make(from: ""), "", "空文本摘要为空")
    let longPreview = ClipboardPreview.make(from: String(repeating: "x", count: 50), maxLength: 10)
    assertEqual(longPreview.count, 10, "超长摘要按上限截断")
    assertEqual(longPreview.hasSuffix("…"), true, "截断处带省略号")
    assertEqual(ClipboardPreview.make(from: "short", maxLength: 0).count, 1, "maxLength≤0 归一化为 1")

    print("✅ Clipboard 哈希 / 忽略判定 / 摘要 works")
}

// MARK: - Test Clipboard 模糊搜索

print("🧪 Testing Clipboard fuzzy search...")
do {
    func item(_ preview: String, app: String? = nil, hash: String = UUID().uuidString) -> ClipboardItem {
        ClipboardItem(kind: .text, preview: preview, contentHash: hash, sourceAppName: app)
    }

    assertEqual(ClipboardFuzzySearch.score(query: "", target: "abc"), 0, "空查询不打分")
    assertEqual(ClipboardFuzzySearch.score(query: "abc", target: ""), 0, "空目标不打分")
    assertEqual(ClipboardFuzzySearch.score(query: "zzz", target: "abc") > 0, false, "无匹配得 0 分")
    assertEqual(ClipboardFuzzySearch.score(query: "abc", target: "abc") > ClipboardFuzzySearch.score(query: "abc", target: "abcdef"), true, "完全相同优于前缀命中")
    assertEqual(ClipboardFuzzySearch.score(query: "bc", target: "abc") > ClipboardFuzzySearch.score(query: "c", target: "abc"), true, "命中更长查询更相关")
    assertEqual(ClipboardFuzzySearch.score(query: "ac", target: "abc") > 0, true, "顺序子序列（跳字）可命中")
    assertEqual(ClipboardFuzzySearch.score(query: "ca", target: "abc"), 0, "乱序字符不再命中（噪音档已删除）")
    assertEqual(ClipboardFuzzySearch.score(query: "ba", target: "ab"), 0, "乱序字母不再命中（噪音档已删除）")

    // 中文搜索
    let chinese = [item("中文测试内容"), item("english text"), item("混合中文")]
    let chineseHits = ClipboardFuzzySearch.rank("中文", items: chinese)
    assertEqual(chineseHits.count, 2, "中文命中 2 条")
    assertEqual(chineseHits.first?.preview, "中文测试内容", "中文前缀命中排第一")

    // 乱序字母
    let letters = [item("digital"), item("github"), item("abc")]
    let letterHits = ClipboardFuzzySearch.rank("git", items: letters)
    assertEqual(letterHits.first?.preview, "github", "前缀命中排最前")
    assertEqual(letterHits.count, 2, "子串命中 2 条")

    // 乱序档删除后的噪音对照：字符齐全但顺序不符 → 0 命中（旧实现会命中长文本）
    let noisy = [item("一些长文本的示例"), item("另一些内容的示例")]
    assertEqual(ClipboardFuzzySearch.rank("的一", items: noisy).count, 0, "「的一」不再命中长文本（乱序噪音档已删除）")
    assertEqual(ClipboardFuzzySearch.score(query: "的一", target: "一些长文本的示例"), 0, "字符齐全但顺序不符不打分")

    // 空查询 / 全空白：按既有排序返回完整列表
    assertEqual(ClipboardFuzzySearch.rank("", items: letters).count, 3, "空查询返回完整列表")
    assertEqual(ClipboardFuzzySearch.rank("   ", items: letters).count, 3, "全空白查询返回完整列表")
    assertEqual(ClipboardFuzzySearch.rank("   ", items: letters).map(\.id), letters.map(\.id), "空查询保持既有排序")

    // 同分稳定：完全相同的两条按入参顺序返回
    let same = [item("same", hash: "h1"), item("same", hash: "h2")]
    assertEqual(ClipboardFuzzySearch.rank("same", items: same).map(\.contentHash), ["h1", "h2"], "同分保持入参顺序")
    // 来源 App 名参与匹配
    assertEqual(ClipboardFuzzySearch.rank("safari", items: [item("任意内容", app: "Safari")]).count, 1, "来源 App 名可被搜索")

    print("✅ Clipboard 模糊搜索 works")
}

// MARK: - Test Clipboard 仓储（SQLite）

print("🧪 Testing ClipboardRepository (SQLite)...")
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    // 建表与迁移：user_version 1 → 2
    var version = -1
    db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
    assertEqual(version, 2, "user_version 迁移到 2")
    assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard_items'").count, 1, "剪贴板表已创建")
    assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_clipboard_content_hash'").count, 1, "内容哈希唯一索引已创建")
    db.migrateIfNeeded()
    db.migrateIfNeeded()
    db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
    assertEqual(version, 2, "重复迁移幂等（user_version 仍为 2）")
    assertEqual(collectQuery(db, sql: "SELECT COUNT(*) FROM clipboard_items").count, 1, "重复迁移不重复建表")

    // 插入
    let first = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-1", text: "hello\nworld",
                                                   sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"))
    assertNotNil(first, "首条插入成功")
    assertEqual(first?.copyCount, 1, "新条目 copy_count 从 1 起")
    assertEqual(first?.preview, "hello world", "摘要由 Core 自动生成（折叠换行）")
    assertEqual(first?.kind, .text, "类型正确")
    let firstID = first?.id

    // 去重：同哈希再插入 → id 不变 + copy_count 自增 + 来源刷新 + 时间置顶
    let later = Date().addingTimeInterval(60)
    let second = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-1", text: "hello\nworld",
                                                    sourceBundleID: "com.google.Chrome", sourceAppName: "Chrome",
                                                    createdAt: later))
    assertEqual(second?.id, firstID, "命中去重保留原 id")
    assertEqual(second?.copyCount, 2, "命中去重 copy_count 自增为 2")
    assertEqual(second?.sourceAppName, "Chrome", "命中去重刷新来源 App")
    assertEqual(second?.createdAt.timeIntervalSince1970, later.timeIntervalSince1970, "命中去重刷新创建时间")
    assertEqual(db.clipboardItemCount(), 1, "去重后仍只有 1 条记录")

    // 无效入参：空哈希不落库
    assertEqual(db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "", text: "无效")) == nil, true, "空内容哈希不落库")
    assertEqual(db.clipboardItemCount(), 1, "空哈希未产生新记录")

    // 图片条目
    assertNotNil(db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "hash-2", preview: "图片 100×50",
                                                     imagePath: "/tmp/clip.png", imageWidth: 100, imageHeight: 50)),
                 "图片条目插入成功")
    assertEqual(db.fetchClipboardItems(kind: nil, limit: 10).count, 2, "分页查询全部 2 条")
    assertEqual(db.fetchClipboardItems(kind: .image, limit: 10).count, 1, "按类型过滤 1 条")
    assertEqual(db.fetchClipboardItems(kind: nil, limit: 0).count, 0, "limit=0 归一化为空结果")
    assertEqual(db.fetchClipboardItems(kind: nil, limit: -5).count, 0, "负 limit 归一化为空结果")
    assertEqual(db.fetchAllClipboardItems(kind: nil).count, 2, "全量查询 2 条")
    if let imageID = db.fetchClipboardItems(kind: .image, limit: 1).first?.id {
        let fetched = db.fetchClipboardItem(id: imageID)
        assertEqual(fetched?.kind, .image, "按 id 回读类型")
        assertEqual(fetched?.imageWidth, 100, "按 id 回读图片宽度")
        assertEqual(fetched?.imageHeight, 50, "按 id 回读图片高度")
        assertEqual(fetched?.isPinned, false, "默认未收藏")
    }
    assertEqual(db.fetchClipboardItem(id: UUID()) == nil, true, "查询不存在的 id 返回 nil")

    // 收藏（收藏即置顶，豁免清理）
    if let firstID {
        assertEqual(db.setClipboardItemPinned(id: firstID, isPinned: true), true, "收藏成功")
        let ordered = db.fetchAllClipboardItems(kind: nil)
        assertEqual(ordered.first?.id, firstID, "收藏项排在最前")
        assertEqual(ordered.first?.pinnedAt != nil, true, "收藏时间已写入")
        assertEqual(db.setClipboardItemPinned(id: firstID, isPinned: false), true, "取消收藏成功")
        assertEqual(db.fetchClipboardItem(id: firstID)?.pinnedAt == nil, true, "取消收藏清空收藏时间")
    }
    assertEqual(db.setClipboardItemPinned(id: UUID(), isPinned: true), false, "收藏不存在的 id 返回 false")

    // 清空：保留收藏
    if let firstID {
        _ = db.setClipboardItemPinned(id: firstID, isPinned: true)
    }
    assertEqual(db.clearClipboardItems(keepingPinned: true), 1, "清空删除 1 条非收藏")
    assertEqual(db.clipboardItemCount(), 1, "清空后仅剩收藏项")
    assertEqual(db.clearClipboardItems(keepingPinned: false), 1, "全清删除收藏项")
    assertEqual(db.clipboardItemCount(), 0, "全部清空")

    // 删除单条
    let doomed = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-3", text: "del-me"))
    assertNotNil(doomed, "删除测试条目插入成功")
    if let doomed {
        assertEqual(db.deleteClipboardItem(id: doomed.id), true, "删除单条成功")
    }
    assertEqual(db.deleteClipboardItem(id: UUID()), false, "删除不存在的 id 返回 false")
    assertEqual(db.clipboardItemCount(), 0, "删除后计数为 0")

    print("✅ ClipboardRepository 建表 / 迁移 / 去重 / 收藏 / 删除 / 清空 works")
}

// MARK: - Test Clipboard 全文检索（SQL LIKE + 元字符转义）

print("\n🧪 Testing Clipboard full-text search (SQL LIKE)...")
do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let base = Date()

    // 1) 全文命中：关键词只出现在 text 第 201 字之后（preview 只存前 200 字，旧实现搜不到）
    let filler = String(repeating: "甲", count: 250)
    guard let deep = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-deep",
                                                        text: filler + "DEEPNEEDLE" + filler,
                                                        createdAt: base)) else { exit(1) }
    assertEqual(deep.preview.count, 200, "摘要截断为 200 字")
    assertEqual(deep.preview.contains("DEEPNEEDLE"), false, "关键词位于摘要截断点之后（旧实现失配前提）")
    assertEqual(db.searchClipboardItems(query: "DEEPNEEDLE", limit: 10).map(\.id), [deep.id], "全文检索命中第 201 字之后的关键词")
    assertEqual(db.searchClipboardItems(query: "DEEPneedle", limit: 10).map(\.id), [deep.id], "大小写不敏感命中 text")

    // 2) LIKE 元字符转义：% / _ / \ 只按字面匹配（不转义时「%」「_」会命中任意条目）
    guard let metas = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-meta",
                                                          text: "进度 100%_done C:\\tmp\\a",
                                                          createdAt: base.addingTimeInterval(1))),
          let plain = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-plain",
                                                          text: "普通内容没有元字符",
                                                          createdAt: base.addingTimeInterval(2))) else { exit(1) }
    assertEqual(ClipboardLIKEPattern.escape("a%b_c\\d"), "a\\%b\\_c\\\\d", "转义函数：逐个元字符前置反斜杠")
    assertEqual(ClipboardLIKEPattern.escape("%_\\"), "\\%\\_\\\\", "转义函数：纯元字符串")
    assertEqual(ClipboardLIKEPattern.escape("中文abc"), "中文abc", "转义函数：无元字符原样返回")
    assertEqual(ClipboardLIKEPattern.contains("ab"), "%ab%", "包含模式拼装 %…%")
    assertEqual(db.searchClipboardItems(query: "%", limit: 50).map(\.id), [metas.id], "% 只按字面匹配（非通配符）")
    assertEqual(db.searchClipboardItems(query: "_", limit: 50).map(\.id), [metas.id], "_ 只按字面匹配（非单字符通配）")
    assertEqual(db.searchClipboardItems(query: "\\", limit: 50).map(\.id), [metas.id], "反斜杠只按字面匹配（转义符本身）")
    assertEqual(db.searchClipboardItems(query: "100%_done", limit: 50).map(\.id), [metas.id], "混合元字符查询精确命中")
    assertEqual(db.searchClipboardItems(query: "普通", limit: 50).map(\.id), [plain.id], "无元字符查询照常命中")

    // 3) 单引号 / 注入串：走绑定参数，不报错不注入
    guard let quoted = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-quote",
                                                           text: "it's O'Brien",
                                                           createdAt: base.addingTimeInterval(3))) else { exit(1) }
    assertEqual(db.searchClipboardItems(query: "it's", limit: 50).map(\.id), [quoted.id], "含单引号查询正常命中")
    assertEqual(db.searchClipboardItems(query: "O'Brien", limit: 50).map(\.id), [quoted.id], "含单引号正文可检索")
    assertEqual(db.searchClipboardItems(query: "'; DROP TABLE clipboard_items;--", limit: 50).count, 0, "注入串无命中且不报错")
    assertEqual(db.clipboardItemCount(), 4, "注入串查询后表完好（条数不变）")

    // 4) 来源 App 名参与匹配（大小写不敏感）
    guard let safari = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-app",
                                                           text: "https://example.com",
                                                           sourceAppName: "Safari",
                                                           createdAt: base.addingTimeInterval(4))) else { exit(1) }
    assertEqual(db.searchClipboardItems(query: "SAFARI", limit: 50).map(\.id), [safari.id], "来源 App 名大小写不敏感参与匹配")

    // 5) NULL text 条目（图片）：preview / 来源名仍能命中，不因三值逻辑整体失配
    guard let picture = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "search-image",
                                                            preview: "图片 100×50", imagePath: "/tmp/clip.png",
                                                            imageWidth: 100, imageHeight: 50,
                                                            sourceAppName: "Preview.app",
                                                            createdAt: base.addingTimeInterval(5))) else { exit(1) }
    assertEqual(picture.text == nil, true, "图片条目 text 列为 NULL")
    assertEqual(db.searchClipboardItems(query: "图片", limit: 50).map(\.id), [picture.id], "NULL text 条目按 preview 命中")
    assertEqual(db.searchClipboardItems(query: "preview.app", limit: 50).map(\.id), [picture.id], "NULL text 条目按来源 App 名命中")
    assertEqual(db.searchClipboardItems(query: "压根不存在的串", limit: 50).count, 0, "无命中返回 []")

    // 6) 空串 / 全空白 / limit ≤ 0 → []
    assertEqual(db.searchClipboardItems(query: "", limit: 50).count, 0, "空查询返回 []")
    assertEqual(db.searchClipboardItems(query: "   \n\t ", limit: 50).count, 0, "全空白查询返回 []")
    assertEqual(db.searchClipboardItems(query: "普通", limit: 0).count, 0, "limit=0 返回 []")
    assertEqual(db.searchClipboardItems(query: "普通", limit: -5).count, 0, "负 limit 返回 []")

    // 7) 排序：收藏优先 + created_at 倒序（与 fetchClipboardItems 一致）
    guard let older = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-ord-old",
                                                          text: "命中标记 旧",
                                                          createdAt: base.addingTimeInterval(-100))),
          let newer = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "search-ord-new",
                                                          text: "命中标记 新",
                                                          createdAt: base.addingTimeInterval(100))) else { exit(1) }
    assertEqual(db.searchClipboardItems(query: "命中标记", limit: 10).map(\.id), [newer.id, older.id], "检索结果按 created_at 倒序")
    assertEqual(db.searchClipboardItems(query: "命中标记", limit: 1).map(\.id), [newer.id], "limit 截断取排序后首条")
    assertEqual(db.setClipboardItemPinned(id: older.id, isPinned: true), true, "收藏较早一条")
    assertEqual(db.searchClipboardItems(query: "命中标记", limit: 10).map(\.id), [older.id, newer.id], "收藏项在检索结果中优先")

    // 8) 极大 limit：Int32 溢出保护，不崩溃
    assertEqual(db.searchClipboardItems(query: "命中标记", limit: Int.max).count, 2, "limit=Int.max 返回全部命中且不崩溃")

    print("✅ Clipboard 全文检索（SQL LIKE / 元字符转义 / NULL / 排序）works")
}

// MARK: - Test Clipboard 超限清理 + Paste Stack

do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }
    let base = Date()

    for index in 0..<12 {
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "prune-\(index)", text: "item \(index)",
                                               createdAt: base.addingTimeInterval(Double(index))))
    }
    assertEqual(db.clipboardItemCount(), 12, "准备 12 条非收藏")
    guard let oldest = db.fetchAllClipboardItems(kind: nil).last else { exit(1) }
    assertEqual(db.setClipboardItemPinned(id: oldest.id, isPinned: true), true, "置顶最早一条")

    assertEqual(db.pruneClipboardItems(maxItems: 5, retentionDays: 30), 6, "超限清理删除 6 条非收藏")
    assertEqual(db.clipboardItemCount(), 6, "剩余 5 条非收藏 + 1 条收藏")
    assertEqual(db.fetchClipboardItem(id: oldest.id) != nil, true, "收藏项豁免超限清理")

    // 保留天数：40 天前的非收藏项被清理
    _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "too-old", text: "old",
                                            createdAt: base.addingTimeInterval(-40 * 86_400)))
    assertEqual(db.pruneClipboardItems(maxItems: 500, retentionDays: 30), 1, "过期条目被按保留天数清理")
    assertEqual(db.clipboardItemCount(), 6, "按天数清理后条数不变（收藏仍在）")

    // 非法入参：负数归一化为默认值，不崩溃
    assertEqual(db.pruneClipboardItems(maxItems: -1, retentionDays: -1), 0, "负 maxItems / 负天数归一化后无删除")
    assertEqual(db.clipboardItemCount(), 6, "非法入参清理后条数不变")

    print("✅ Clipboard 超限清理（收藏豁免 / 负数归一化）works")
}

do {
    let db = DatabaseManager()
    db.initializeInMemory()
    defer { db.close() }

    guard let a = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "s-a", text: "a")),
          let b = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "s-b", text: "b")),
          let c = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "s-c", text: "c")) else { exit(1) }

    db.updateClipboardStackPositions([c.id, a.id])
    let stack = db.fetchClipboardStack()
    assertEqual(stack.count, 2, "栈内 2 条")
    assertEqual(stack.first?.id, c.id, "队首为 c")
    assertEqual(stack.first?.stackPosition, 1, "队首编号 1")
    assertEqual(stack.last?.stackPosition, 2, "队尾编号 2")
    assertEqual(db.fetchClipboardItem(id: b.id)?.stackPosition, nil, "未入栈条目 stack_position 为 NULL")

    db.updateClipboardStackPositions([a.id, c.id])
    assertEqual(db.fetchClipboardStack().map(\.id), [a.id, c.id], "重排后顺序更新")

    db.updateClipboardStackPositions([])
    assertEqual(db.fetchClipboardStack().count, 0, "清空整栈")

    print("✅ Clipboard Paste Stack 顺序持久化 works")
}

// MARK: - Test Clipboard 数据库未初始化容错

do {
    let db = DatabaseManager()
    assertEqual(db.isReady, false, "数据库未初始化")
    assertEqual(db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "x", text: "x")) == nil, true, "未初始化时不写入")
    assertEqual(db.fetchClipboardItem(id: UUID()) == nil, true, "未初始化时按 id 查询返回 nil")
    assertEqual(db.fetchClipboardItems(kind: nil, limit: 10).isEmpty, true, "未初始化时分页查询返回空")
    assertEqual(db.fetchAllClipboardItems(kind: nil).isEmpty, true, "未初始化时全量查询返回空")
    assertEqual(db.setClipboardItemPinned(id: UUID(), isPinned: true), false, "未初始化时收藏返回 false")
    assertEqual(db.deleteClipboardItem(id: UUID()), false, "未初始化时删除返回 false")
    assertEqual(db.clearClipboardItems(keepingPinned: true), 0, "未初始化时清空返回 0")
    assertEqual(db.pruneClipboardItems(maxItems: 1, retentionDays: 1), 0, "未初始化时清理返回 0")
    assertEqual(db.clipboardItemCount(), 0, "未初始化时计数为 0")
    assertEqual(db.searchClipboardItems(query: "任意", limit: 10).isEmpty, true, "未初始化时全文检索返回空")
    assertEqual(db.searchClipboardItems(query: "任意", limit: Int.max).isEmpty, true, "未初始化时全文检索极大 limit 仍为空")
    db.updateClipboardStackPositions([UUID()])
    assertEqual(db.fetchClipboardStack().isEmpty, true, "未初始化时栈为空")
    print("✅ Clipboard 数据库未初始化容错 works")
}

// MARK: - Test Clipboard 协议 Mock 驱动面板数据流

do {
    final class MockClipboardRepository: @unchecked Sendable, ClipboardRepository {
        private let lock = NSLock()
        private var storage: [ClipboardItem] = []

        func saveClipboardItem(_ draft: ClipboardDraft) -> ClipboardItem? {
            let item = ClipboardItem(kind: draft.kind, text: draft.text,
                                     preview: draft.preview ?? ClipboardPreview.make(from: draft.text ?? ""),
                                     contentHash: draft.contentHash, sourceAppName: draft.sourceAppName,
                                     createdAt: draft.createdAt)
            lock.lock(); defer { lock.unlock() }
            storage.insert(item, at: 0)
            return item
        }
        func fetchClipboardItem(id: UUID) -> ClipboardItem? {
            lock.lock(); defer { lock.unlock() }
            return storage.first { $0.id == id }
        }
        func fetchClipboardItems(kind: ClipboardItemKind?, limit: Int) -> [ClipboardItem] {
            guard limit > 0 else { return [] }
            return Array(fetchAllClipboardItems(kind: kind).prefix(limit))
        }
        func fetchAllClipboardItems(kind: ClipboardItemKind?) -> [ClipboardItem] {
            lock.lock(); defer { lock.unlock() }
            return kind == nil ? storage : storage.filter { $0.kind == kind }
        }
        func searchClipboardItems(query: String, limit: Int) -> [ClipboardItem] {
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !keyword.isEmpty, limit > 0 else { return [] }
            return Array(fetchAllClipboardItems(kind: nil).filter { item in
                item.preview.lowercased().contains(keyword)
                    || (item.text ?? "").lowercased().contains(keyword)
                    || (item.sourceAppName ?? "").lowercased().contains(keyword)
            }.prefix(limit))
        }
        func setClipboardItemPinned(id: UUID, isPinned: Bool) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let index = storage.firstIndex(where: { $0.id == id }) else { return false }
            storage[index].isPinned = isPinned
            return true
        }
        func deleteClipboardItem(id: UUID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let before = storage.count
            storage.removeAll { $0.id == id }
            return storage.count != before
        }
        func clearClipboardItems(keepingPinned: Bool) -> Int {
            lock.lock(); defer { lock.unlock() }
            let before = storage.count
            storage.removeAll { keepingPinned ? !$0.isPinned : true }
            return before - storage.count
        }
        func updateClipboardStackPositions(_ orderedIDs: [UUID]) {
            lock.lock(); defer { lock.unlock() }
            for index in storage.indices { storage[index].stackPosition = nil }
            for (offset, id) in orderedIDs.enumerated() {
                if let index = storage.firstIndex(where: { $0.id == id }) { storage[index].stackPosition = offset + 1 }
            }
        }
        func fetchClipboardStack() -> [ClipboardItem] {
            fetchAllClipboardItems(kind: nil).filter { $0.stackPosition != nil }
                .sorted { ($0.stackPosition ?? 0) < ($1.stackPosition ?? 0) }
        }
        func pruneClipboardItems(maxItems: Int, retentionDays: Int) -> Int { 0 }
        func clipboardItemCount() -> Int { fetchAllClipboardItems(kind: nil).count }
    }

    @MainActor
    final class MockClipboardCaptureService: ClipboardCaptureService {
        var isRunning = false
        var onStateChange: ((ClipboardCaptureState) -> Void)?
        var onCapture: ((ClipboardDraft) -> Void)?
        private(set) var captureNowCount = 0
        private(set) var lastState: ClipboardCaptureState = .stopped

        func start() {
            isRunning = true
            lastState = .running
            onStateChange?(.running)
        }
        func stop() {
            isRunning = false
            lastState = .stopped
            onStateChange?(.stopped)
        }
        func captureNow() {
            captureNowCount += 1
            onCapture?(ClipboardDraft(kind: .text, contentHash: "mock-hash", text: "mock 文本"))
        }
    }

    @MainActor
    final class MockClipboardWriter: ClipboardWriter {
        private(set) var written: [ClipboardItem] = []
        private(set) var markDepth = 0
        private(set) var plainText = false

        func write(_ item: ClipboardItem, asPlainText: Bool) -> Bool {
            written.append(item)
            plainText = asPlainText
            return true
        }
        func writeText(_ text: String) -> Bool { true }
        func beginInternalWrite() { markDepth += 1 }
        func endInternalWrite() { markDepth = max(0, markDepth - 1) }
    }

    let repository = MockClipboardRepository()
    let capture = MockClipboardCaptureService()
    let writer = MockClipboardWriter()

    var observedStates: [ClipboardCaptureState] = []
    capture.onStateChange = { observedStates.append($0) }
    capture.onCapture = { draft in
        // 采集 → 落库（面板数据流的 Core 侧最短闭环）
        _ = repository.saveClipboardItem(draft)
    }

    capture.start()
    assertEqual(capture.isRunning, true, "采集服务已启动")
    capture.captureNow()
    assertEqual(capture.captureNowCount, 1, "手动采集触发一次")
    assertEqual(repository.fetchAllClipboardItems(kind: nil).count, 1, "面板通过协议读到 1 条")

    let items = repository.fetchAllClipboardItems(kind: nil)
    assertEqual(ClipboardFuzzySearch.rank("mock", items: items).count, 1, "面板搜索命中 mock 条目")
    assertEqual(repository.searchClipboardItems(query: "mock", limit: 10).count, 1, "面板全文检索命中 mock 条目")
    assertEqual(repository.searchClipboardItems(query: "  ", limit: 10).count, 0, "面板全文检索空查询返回空")
    assertEqual(repository.setClipboardItemPinned(id: items[0].id, isPinned: true), true, "面板收藏成功")
    assertEqual(repository.clearClipboardItems(keepingPinned: true), 0, "收藏项豁免清空")
    repository.updateClipboardStackPositions([items[0].id])
    assertEqual(repository.fetchClipboardStack().count, 1, "面板入栈成功")

    writer.beginInternalWrite()
    assertEqual(writer.write(items[0], asPlainText: false), true, "写回系统剪贴板成功")
    writer.endInternalWrite()
    assertEqual(writer.markDepth, 0, "自激标记已清除")
    assertEqual(writer.written.count, 1, "写回条目数正确")

    capture.stop()
    assertEqual(capture.isRunning, false, "采集服务已停止")
    assertEqual(observedStates, [.running, .stopped], "状态回调顺序正确")

    print("✅ Clipboard 三协议 Mock 驱动面板数据流 works")
}

// MARK: - Test ClipboardRelativeTime（相对时间格式化，Core 纯函数）

print("🧪 Testing ClipboardRelativeTime...")
do {
    // 固定参照时间，保证断言确定（与实现同为本地时区）
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func rel(_ offset: TimeInterval) -> String {
        ClipboardRelativeTime.string(from: now.addingTimeInterval(offset), now: now)
    }

    // 常规档位：刚刚 / 分钟 / 小时 / 天
    assertEqual(rel(0), "刚刚", "时间差为 0：刚刚")
    assertEqual(rel(-10), "刚刚", "10 秒前：刚刚")
    assertEqual(rel(-90), "1 分钟前", "90 秒：1 分钟前")
    assertEqual(rel(-120), "2 分钟前", "120 秒：2 分钟前")
    assertEqual(rel(-7_200), "2 小时前", "2 小时：2 小时前")
    assertEqual(rel(-86_400 * 3), "3 天前", "3 天：3 天前")
    assertEqual(rel(-86_400 * 29), "29 天前", "29 天：29 天前")

    // 更早：≥ 30 天回退为「M月d日」
    let formatter = DateFormatter()
    formatter.dateFormat = "M月d日"
    assertEqual(rel(-86_400 * 30), formatter.string(from: now.addingTimeInterval(-86_400 * 30)), "30 天：回退为 M月d日")
    let farPastText: String? = ClipboardRelativeTime.string(from: now.addingTimeInterval(-86_400 * 400), now: now)
    assertNotNil(farPastText, "远期时间仍产出文案")
    if let farPastText {
        assertEqual(farPastText, formatter.string(from: now.addingTimeInterval(-86_400 * 400)), "远期时间同样为 M月d日")
    }

    // 边界：60 秒、60 分、24 小时与 30 天的分档切换点（含切换前一秒）
    assertEqual(rel(-59), "刚刚", "59 秒：仍为刚刚")
    assertEqual(rel(-60), "1 分钟前", "60 秒：切换为分钟")
    assertEqual(rel(-3_540), "59 分钟前", "59 分：59 分钟前")
    assertEqual(rel(-3_600), "1 小时前", "60 分：切换为小时")
    assertEqual(rel(-82_800), "23 小时前", "23 小时：23 小时前")
    assertEqual(rel(-86_400), "1 天前", "24 小时：切换为天")
    assertEqual(rel(-86_400 * 30 + 1), "29 天前", "30 天前一秒：仍按天")

    // 异常入参：时间差为负（目标时间在未来，时钟漂移）统一按「刚刚」处理
    assertEqual(rel(3_600), "刚刚", "未来 1 小时：按刚刚处理")
    assertEqual(rel(86_400 * 400), "刚刚", "远期未来时间：仍按刚刚处理")

    print("✅ ClipboardRelativeTime works")
}

// MARK: - Test MenuPanelMetrics（菜单面板取数口径，Core 纯函数）

print("\n🧪 Testing MenuPanelMetrics...")
do {
    // 近 6 日柱状图：入参今天在最前（降序），出参改成时间正序且今天标尾
    let entries: [(label: String, rx: UInt64, tx: UInt64)] = [
        ("10/16", 5_600_000_000, 800_000_000),
        ("10/15", 2_000_000_000, 300_000_000),
        ("10/14", 1_800_000_000, 200_000_000),
    ]
    let six = MenuPanelMetrics.recentDays(entries: entries, limit: 6)
    assertEqual(six.count, 3, "不足 6 天时按实际条数返回")
    assertEqual(six.map(\.label), ["10/14", "10/15", "10/16"], "时间正序：最左最早、最右今天")
    assertEqual(six.last?.isToday, true, "最后一条标记为今天")
    assertEqual(six.first?.isToday, false, "历史条目不是今天")

    let capped = MenuPanelMetrics.recentDays(entries: entries, limit: 2)
    assertEqual(capped.map(\.label), ["10/15", "10/16"], "limit 取最近 N 天并保持正序")
    assertEqual(capped.last?.isToday, true, "截断后今天仍标记")
    assertEqual(MenuPanelMetrics.recentDays(entries: entries, limit: 0).count, 0, "limit=0 返回空")
    assertEqual(MenuPanelMetrics.recentDays(entries: entries, limit: -3).count, 0, "负 limit 返回空")
    assertEqual(MenuPanelMetrics.recentDays(entries: [], limit: 6).count, 0, "无数据返回空")

    // 今日流量占比：下行 /（下行 + 上行）
    assertEqual(MenuPanelMetrics.downShare(rx: 8_000, tx: 2_000), 0.8, "80% 下行占比")
    assertEqual(MenuPanelMetrics.downShare(rx: 1_000, tx: 0), 1.0, "只有下行时占比 1")
    assertEqual(MenuPanelMetrics.downShare(rx: 0, tx: 0), 0.0, "总量为 0 时占比 0")

    // 柱高比例：相对最大值；全 0 不产生 NaN
    assertEqual(MenuPanelMetrics.barRatios(values: [0, 50, 100]), [0, 0.5, 1], "相对最大值归一化")
    assertEqual(MenuPanelMetrics.barRatios(values: [0, 0]), [0, 0], "全 0 时高度全 0")
    assertEqual(MenuPanelMetrics.barRatios(values: []).isEmpty, true, "空数组返回空")

    // 速率拆分：数值段 + 单位段
    let zero = MenuPanelMetrics.speedParts(0)
    assertEqual(zero.value, "0", "0 速率数值段")
    assertEqual(zero.unit, "B/s", "0 速率单位段")
    let kilo = MenuPanelMetrics.speedParts(1_500)
    assertEqual(kilo.value, "2", "1.5K 数值段四舍五入")
    assertEqual(kilo.unit, "KB/s", "1.5K 单位段")
    let mega = MenuPanelMetrics.speedParts(1_200_000)
    assertEqual(mega.value, "1.2", "1.2M 数值段")
    assertEqual(mega.unit, "MB/s", "1.2M 单位段")
    let giga = MenuPanelMetrics.speedParts(2_300_000_000)
    assertEqual(giga.value, "2.3", "2.3G 数值段")
    assertEqual(giga.unit, "GB/s", "2.3G 单位段")
    let negative = MenuPanelMetrics.speedParts(-1_500_000)
    assertEqual(negative.value, "1.5", "负速率按绝对值展示")
    assertEqual(negative.unit, "MB/s", "负速率单位不变")

    // 活跃进程 Top N：零流量过滤 + 总量降序 + 上限截断
    let processes = [
        ProcessNetUsage(name: "Safari", pid: 1, bytesIn: 100, bytesOut: 100),
        ProcessNetUsage(name: "idle", pid: 2, bytesIn: 0, bytesOut: 0),
        ProcessNetUsage(name: "Chrome", pid: 3, bytesIn: 900, bytesOut: 100),
        ProcessNetUsage(name: "Slack", pid: 4, bytesIn: 50, bytesOut: 50),
    ]
    let topTwo = MenuPanelMetrics.topProcesses(processes, limit: 2)
    assertEqual(topTwo.map(\.name), ["Chrome", "Safari"], "按总流量降序取 Top2")
    assertEqual(MenuPanelMetrics.topProcesses(processes, limit: 10).count, 3, "零流量进程被过滤")
    assertEqual(MenuPanelMetrics.topProcesses(processes, limit: 0).isEmpty, true, "limit=0 返回空")

    print("✅ MenuPanelMetrics 面板取数口径 works")
}

// MARK: - 局域网文件互传

runTransferTests()

// MARK: - 扫码接收（二维码 + 浏览器直传）

runScanTests()

// MARK: - 计费额度（provider 抽象 + Ollama 响应解码）

runBillingTests()

// MARK: - 额度阈值提醒（5%/4%/3%/2%/1%）

runBillingAlertTests()

// MARK: - Open Design 额度（归一化 / 工作区发现 / 窗口映射 / 用量聚合）

runOpenDesignBillingTests()

// MARK: - Done

print("\n🎉 所有测试通过！")
