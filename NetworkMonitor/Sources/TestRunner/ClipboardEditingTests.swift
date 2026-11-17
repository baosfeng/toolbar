import Foundation
import SQLite3
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 剪贴板条目编辑与手动新建

/// 编辑 / 新建两条写入路径的守门测试
///
/// 钉住四件事（本批验收口径）：
/// 1. 编辑后 content_hash **重算**，不是沿用旧值；copy_count 与 created_at 不动（编辑不等于又复制一次）；
/// 2. 重算哈希撞上别的条目时：保留当前条目，被冲突那条按「同内容的旧记录」删除，copy_count 求和、收藏取或；
/// 3. 空内容一律不保存（规范化后空白 → nil），图片 / 文件条目拒绝编辑；
/// 4. 手动新建不记录来源 App，去重口径与采集一致（同内容自增 copy_count 并置顶）。
func runClipboardEditingTests() {
    print("🧪 Testing 剪贴板编辑 / 新建...")

    // MARK: 编辑：哈希重算 + 元信息不动

    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        guard let original = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-old",
                                                                text: "旧正文",
                                                                sourceBundleID: "com.apple.Safari",
                                                                sourceAppName: "Safari",
                                                                createdAt: createdAt)) else {
            assertEqual(false, true, "编辑用例的前置条目插入失败")
            return
        }

        let edited = db.updateClipboardItemText(id: original.id, text: "新正文\n第二行", preview: "新正文 第二行")
        assertNotNil(edited, "编辑已存在的文本条目成功")
        assertEqual(edited?.text, "新正文\n第二行", "正文已更新")
        assertEqual(edited?.preview, "新正文 第二行", "摘要已更新")
        assertEqual(edited?.contentHash, ClipboardContentHasher.hash(text: "新正文\n第二行"),
                    "content_hash 按新正文重算（不是沿用旧哈希）")
        assertEqual(edited?.contentHash == "hash-old", false, "哈希确实变了")
        assertEqual(edited?.copyCount, 1, "编辑不自增复制次数（编辑不等于又复制了一次）")
        assertEqual(edited?.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970,
                    "编辑不改创建时间（不置顶）")
        assertEqual(edited?.sourceAppName, "Safari", "编辑保留来源 App")
        assertEqual(db.clipboardItemCount(), 1, "编辑不新增行")
        assertEqual(db.fetchClipboardItem(id: original.id)?.text, "新正文\n第二行", "按 id 回读已是新正文")

        // 摘要留空时由仓储按正文生成
        let blankPreview = db.updateClipboardItemText(id: original.id, text: "只有正文", preview: "   ")
        assertEqual(blankPreview?.preview, "只有正文", "摘要为空白时按正文自动生成")

        // 规范化：首尾空白被去掉，换行统一
        let normalized = db.updateClipboardItemText(id: original.id, text: "  \r\n甲\r\n乙\n  ", preview: "")
        assertEqual(normalized?.text, "甲\n乙", "正文按采集同口径规范化（去首尾空白 + 统一换行）")
        assertEqual(normalized?.contentHash, ClipboardContentHasher.hash(text: "甲\n乙"),
                    "规范化后的正文参与哈希计算")

        print("✅ 剪贴板编辑：哈希重算 / 元信息保持 works")
    }

    // MARK: 编辑：空内容与不支持类型

    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        guard let text = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "keep-hash", text: "原样")) else {
            assertEqual(false, true, "空内容用例的前置条目插入失败")
            return
        }
        assertEqual(db.updateClipboardItemText(id: text.id, text: "", preview: "") == nil, true,
                    "空串不保存（空内容没有可用的内容哈希）")
        assertEqual(db.updateClipboardItemText(id: text.id, text: "  \n\t ", preview: "") == nil, true,
                    "纯空白不保存")
        assertEqual(db.fetchClipboardItem(id: text.id)?.text, "原样", "被拒绝的编辑没有改动库里那一条")
        assertEqual(db.updateClipboardItemText(id: UUID(), text: "正文", preview: "") == nil, true,
                    "编辑不存在的条目返回 nil")

        guard let image = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "img-hash",
                                                              preview: "图片 10×10",
                                                              imagePath: "/tmp/none.png",
                                                              imageWidth: 10, imageHeight: 10)) else {
            assertEqual(false, true, "图片条目插入失败")
            return
        }
        assertEqual(db.updateClipboardItemText(id: image.id, text: "想改成文本", preview: "") == nil, true,
                    "图片条目拒绝正文编辑（走各自路径）")
        assertEqual(db.fetchClipboardItem(id: image.id)?.kind, .image, "图片条目类型未被改写")

        print("✅ 剪贴板编辑：空内容拒绝 / 类型边界 works")
    }

    // MARK: 编辑：哈希冲突合并

    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(60)
        // 冲突判据是「按新正文重算出来的真实哈希」，所以两条前置条目必须用真实哈希建
        let alphaHash = ClipboardContentHasher.hash(text: "alpha") ?? "hash-alpha"
        guard let target = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "hash-target",
                                                               text: "将被改写成 alpha", createdAt: older)),
              let existing = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: alphaHash,
                                                                 text: "alpha", createdAt: newer)) else {
            assertEqual(false, true, "冲突用例的前置条目插入失败")
            return
        }
        // 让「已存在于库里的那条」被收藏且复制过多次，合并后这些都要保住
        _ = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: alphaHash, text: "alpha", createdAt: newer))
        _ = db.setClipboardItemPinned(id: existing.id, isPinned: true)

        let merged = db.updateClipboardItemText(id: target.id, text: "alpha", preview: "alpha")
        assertNotNil(merged, "改成与已有条目相同的内容可以保存")
        assertEqual(merged?.id, target.id, "保留当前（正在编辑的）条目，不切成被冲突那条")
        assertEqual(merged?.contentHash, alphaHash, "哈希就是两者共同的那一个")
        assertEqual(merged?.copyCount, 3, "复制次数求和：当前 1 次 + 被冲突那条 2 次")
        assertEqual(merged?.isPinned, true, "收藏态取或：任一条被收藏就保持收藏")
        assertEqual(merged?.createdAt.timeIntervalSince1970, older.timeIntervalSince1970,
                    "创建时间仍属于当前条目（编辑不置顶）")
        assertEqual(db.fetchClipboardItem(id: existing.id) == nil, true, "被冲突那条作为同内容旧记录被删除")
        assertEqual(db.clipboardItemCount(), 1, "合并后只留一行")

        // 自撞（内容没改）不算冲突：同一条再保存一次不会删自己
        let sameAgain = db.updateClipboardItemText(id: target.id, text: "alpha", preview: "alpha")
        assertEqual(sameAgain?.id, target.id, "把内容改回自己不变时仍返回自身")
        assertEqual(db.clipboardItemCount(), 1, "自撞不产生额外行")

        print("✅ 剪贴板编辑：哈希冲突合并（保留当前条目 / 次数求和 / 收藏取或）works")
    }

    // MARK: 手动新建

    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        guard let created = db.createClipboardItem(text: "手写的第一条") else {
            assertEqual(false, true, "手动新建失败")
            return
        }
        assertEqual(created.text, "手写的第一条", "新建条目正文正确")
        assertEqual(created.kind, .text, "新建条目类型为纯文本")
        assertEqual(created.contentHash, ClipboardContentHasher.hash(text: "手写的第一条"),
                    "新建条目按同一口径计算内容哈希")
        assertEqual(created.preview, "手写的第一条", "新建条目摘要由 Core 生成")
        assertEqual(created.sourceAppName == nil, true, "手动新建不记录来源 App 名")
        assertEqual(created.sourceBundleID == nil, true, "手动新建不记录来源 bundleID")
        assertEqual(created.copyCount, 1, "新建条目复制次数从 1 起")
        assertEqual(db.clipboardItemCount(), 1, "已经落库")

        assertEqual(db.createClipboardItem(text: "   \n ") == nil, true, "空白内容不落库")
        assertEqual(db.clipboardItemCount(), 1, "空白内容没有产生新行")

        // 去重口径与采集一致：同内容再建一次只是自增复制次数并置顶
        let again = db.createClipboardItem(text: "手写的第一条")
        assertEqual(again?.id, created.id, "同内容再建一次命中去重，保留原 id")
        assertEqual(again?.copyCount, 2, "同内容再建一次复制次数自增")
        assertEqual(db.clipboardItemCount(), 1, "去重后仍只有一行")

        // 新建项按创建时间倒序排到列表头
        _ = db.createClipboardItem(text: "后建的一条")
        assertEqual(db.fetchAllClipboardItems(kind: nil).first?.text, "后建的一条", "新建项排在列表头")

        print("✅ 剪贴板新建：落库 / 无来源 / 空内容拒绝 / 去重 works")
    }

    // MARK: 未初始化容错

    do {
        let db = DatabaseManager()
        assertEqual(db.updateClipboardItemText(id: UUID(), text: "正文", preview: "") == nil, true,
                    "数据库未初始化时编辑返回 nil")
        assertEqual(db.createClipboardItem(text: "正文") == nil, true, "数据库未初始化时新建返回 nil")
        print("✅ 剪贴板编辑 / 新建：未初始化容错 works")
    }

    // MARK: 编辑态口径（纯逻辑）

    do {
        let textItem = ClipboardItem(kind: .text, text: "正文", contentHash: "edit-text")
        assertEqual(ClipboardEditSession.rejection(for: textItem) == nil, true, "文本条目可以编辑")
        let rtfItem = ClipboardItem(kind: .rtf, text: "正文", contentHash: "edit-rtf")
        assertEqual(ClipboardEditSession.rejection(for: rtfItem) == nil, true, "富文本条目（落纯文本）可以编辑")
        let imageItem = ClipboardItem(kind: .image, preview: "图片", contentHash: "edit-image")
        assertEqual(ClipboardEditSession.rejection(for: imageItem), .unsupportedKind, "图片条目不可编辑")
        let fileItem = ClipboardItem(kind: .file, text: "/tmp/a", contentHash: "edit-file")
        assertEqual(ClipboardEditSession.rejection(for: fileItem), .unsupportedKind, "文件条目不可编辑")

        assertEqual(ClipboardEditSession.initialText(for: textItem), "正文", "编辑初值取完整正文")
        let previewOnly = ClipboardItem(kind: .text, preview: "只有摘要", contentHash: "edit-preview")
        assertEqual(ClipboardEditSession.initialText(for: previewOnly), "只有摘要", "正文缺失时退回摘要")

        assertEqual(ClipboardEditSession.canSave(text: "有内容"), true, "有内容可以保存")
        assertEqual(ClipboardEditSession.canSave(text: "  \n "), false, "纯空白不允许保存")
        assertEqual(ClipboardEditSession.canSave(text: ""), false, "空串不允许保存")

        assertEqual(ClipboardEditSession.Origin.existing(UUID()).isDraft, false, "编辑已有条目不是新建")
        assertEqual(ClipboardEditSession.Origin.draft.isDraft, true, "新建来源标记为 draft")
        assertEqual(ClipboardEditSession.Origin.draft.itemID == nil, true, "新建在落库前没有条目 id")
        assertEqual(ClipboardEditSession.failureHint(.emptyText), "内容为空，未保存", "空内容提示文案")
        assertEqual(ClipboardEditSession.failureHint(.unsupportedKind), "只有文本条目可以编辑", "类型不支持提示文案")

        print("✅ 剪贴板编辑态口径 works")
    }
}
