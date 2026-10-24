import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板面板数据流与相对时间（从 main.swift 拆出）

// MARK: - 剪贴板协议 Mock 驱动面板数据流

// 原 main.swift 顶层代码在 Swift 6 下处于 MainActor 隔离，搬入函数后显式标注以保持同等隔离语义。
@MainActor
func runClipboardPanelMockTests() {
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

}

// MARK: - ClipboardRelativeTime 相对时间格式化

func runClipboardRelativeTimeTests() {
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

}

