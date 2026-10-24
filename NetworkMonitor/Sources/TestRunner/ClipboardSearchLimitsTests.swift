import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板全文检索与超限清理（从 main.swift 拆出）

// MARK: - 剪贴板全文检索（SQL LIKE + 元字符转义）

func runClipboardFullTextSearchTests() {
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

}

// MARK: - 剪贴板超限清理 + Paste Stack

func runClipboardLimitsTests() {
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

}

