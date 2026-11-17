import Foundation
import SQLite3
import NetworkMonitorCore

// MARK: - 剪贴板板仓储（建 / 改名 / 移动 / 删板连带删条目 / 双重豁免 / 批量移入移出）

/// 板领域的守恒测试 —— 从 ClipboardRepositoryTests 独立成文件（那边已贴着单文件体积上限）
///
/// 钉住三件事：板 CRUD 的落库结果、删板连带删条目、以及「板归属」与「收藏」两条
/// 独立豁免语义在超限清理里都生效（任一条失效，用户钉住的内容就会被清掉）。
func runClipboardBoardTests() {
    print("🧪 Testing 剪贴板板仓储（CRUD / 删除连带 / 双重豁免）...")
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }

        // 建表：v4 段可重放，板表与索引就位
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='table' AND name='clipboard_boards'").count, 1,
                    "板表已创建")
        assertEqual(collectQuery(db, sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_clipboard_board'").count, 1,
                    "板归属索引已创建")
        var version = -1
        db.query(sql: "PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        assertEqual(version, Int(ClipboardSchema.latestVersion), "迁移版本停在最新（含 v4）")

        // 建板：空白名归一化、顺序递增、色板下标轮转
        guard let first = db.createBoard(name: "  资料  "),
              let second = db.createBoard(name: "   ") else { exit(1) }
        assertEqual(first.name, "资料", "板名去首尾空白")
        assertEqual(second.name, "未命名板", "空白板名归一化为「未命名板」")
        assertEqual(first.colorIndex, 0, "首块板取色板 0 号")
        assertEqual(second.colorIndex, 1, "第二块板色板下标递增")
        assertEqual(first.sortOrder < second.sortOrder, true, "后建的板排在后面")
        assertEqual(db.fetchBoards().map(\.id), [first.id, second.id], "全部板按顺序返回")

        // 改名：命中返回 true，未命中返回 false
        assertEqual(db.renameBoard(id: first.id, name: "工作"), true, "改名命中返回 true")
        assertEqual(db.fetchBoards().first?.name, "工作", "改名已落库")
        assertEqual(db.renameBoard(id: UUID(), name: "无主"), false, "改名不存在的板返回 false")

        // 移动条目：进入板 / 移回未归类
        guard let item = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "board-item", text: "板内条目")) else { exit(1) }
        assertEqual(db.moveItemToBoard(itemID: item.id, boardID: first.id), true, "移入板成功")
        assertEqual(db.fetchClipboardItem(id: item.id)?.boardID, first.id, "board_id 已落库")
        assertEqual(db.fetchClipboardItems(boardID: first.id).map(\.id), [item.id], "板内查询命中该条")
        assertEqual(db.fetchClipboardItems(boardID: second.id).isEmpty, true, "别的板看不到它")
        assertEqual(db.moveItemToBoard(itemID: item.id, boardID: nil), true, "移回未归类成功")
        assertEqual(db.fetchClipboardItem(id: item.id)?.boardID == nil, true, "board_id 清空为 NULL")
        assertEqual(db.moveItemToBoard(itemID: UUID(), boardID: first.id), false, "移动不存在的条目返回 false")

        print("✅ 剪贴板板 CRUD / 移动 works")
    }

    // 删板：连带删掉板内条目并把被删行返回（供上层回收图片）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        guard let board = db.createBoard(name: "过期项目"),
              let inside = db.saveClipboardItem(ClipboardDraft(kind: .image, contentHash: "board-doomed",
                                                               preview: "图片", imagePath: "/tmp/board-doomed.png",
                                                               imageWidth: 10, imageHeight: 10)),
              let outside = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "board-kept", text: "板外条目")),
              db.moveItemToBoard(itemID: inside.id, boardID: board.id) else { exit(1) }

        let doomed = db.deleteBoard(id: board.id)
        assertEqual(doomed.map(\.id), [inside.id], "删板返回板内被删条目（供图片回收）")
        assertEqual(db.fetchClipboardItem(id: inside.id) == nil, true, "板内条目已连带删除")
        assertEqual(db.fetchClipboardItem(id: outside.id) != nil, true, "板外条目不受影响")
        assertEqual(db.fetchBoards().isEmpty, true, "板本身已删除")
        assertEqual(db.deleteBoard(id: board.id).isEmpty, true, "重复删板返回空数组")
        assertEqual(db.clipboardItemCount(), 1, "删板后只剩板外 1 条")

        print("✅ 剪贴板删板连带删条目 / 板外不受影响 works")
    }

    // 双重豁免：收藏（is_pinned）与板归属（board_id）各自豁免超限清理与过期清理
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        let base = Date()
        guard let board = db.createBoard(name: "长期") else { exit(1) }
        // 三条都是最老的行：不豁免的话会同时被「保留天数」和「条数上限」清掉
        guard let pinned = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "exempt-pinned",
                                                               text: "收藏项", createdAt: base.addingTimeInterval(-90 * 86_400))),
              let boarded = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "exempt-board",
                                                                text: "板内项", createdAt: base.addingTimeInterval(-80 * 86_400))),
              let plain = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "exempt-plain",
                                                              text: "普通项", createdAt: base.addingTimeInterval(-70 * 86_400))) else { exit(1) }
        _ = db.setClipboardItemPinned(id: pinned.id, isPinned: true)
        _ = db.moveItemToBoard(itemID: boarded.id, boardID: board.id)

        let pruned = db.pruneClipboardItems(maxItems: 1, retentionDays: 30)
        assertEqual(pruned.map(\.id), [plain.id], "只有既不收藏也不在板内的条目被清理")
        assertEqual(db.fetchClipboardItem(id: pinned.id) != nil, true, "收藏项豁免清理")
        assertEqual(db.fetchClipboardItem(id: boarded.id) != nil, true, "板内条目豁免清理（永不过期）")
        assertEqual(db.clipboardItemCount(), 2, "清理后剩收藏 + 板内两条")

        // 板内条目不占条数额度：上限 1 时普通项被清，两条豁免项还在
        assertEqual(db.fetchClipboardItems(boardID: board.id).map(\.id), [boarded.id], "板内条目仍可取到")
        assertEqual(db.fetchBoards().count, 1, "清理不动板表")

        print("✅ 剪贴板双重豁免（收藏 + 板归属）works")
    }

    // 批量移入 / 移出：多选路径逐条落库，板内查询与计数都跟着变（与右键「移到板…」同口径）
    do {
        let db = DatabaseManager()
        db.initializeInMemory()
        defer { db.close() }
        guard let work = db.createBoard(name: "工作"),
              let later = db.createBoard(name: "稍后"),
              let a = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "bulk-a", text: "批量 A")),
              let b = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "bulk-b", text: "批量 B")),
              let c = db.saveClipboardItem(ClipboardDraft(kind: .text, contentHash: "bulk-c", text: "留在外面")) else { exit(1) }

        // 批量移入一块板：两次调用都命中
        let batchMoved = [a.id, b.id].reduce(into: 0) {
            if db.moveItemToBoard(itemID: $1, boardID: work.id) { $0 += 1 }
        }
        assertEqual(batchMoved, 2, "批量移入两条都命中")
        assertEqual(Set(db.fetchClipboardItems(boardID: work.id).map(\.id)), Set([a.id, b.id]), "板内查询含两条")
        assertEqual(db.fetchClipboardItem(id: c.id)?.boardID == nil, true, "未选中的条目仍在板外")

        // 只把其中一条转到另一块板：原板只剩一条，新板一条
        assertEqual(db.moveItemToBoard(itemID: b.id, boardID: later.id), true, "改投另一块板命中")
        assertEqual(db.fetchClipboardItems(boardID: work.id).map(\.id), [a.id], "原板只剩一条")
        assertEqual(db.fetchClipboardItems(boardID: later.id).map(\.id), [b.id], "新板拿到这一条")

        // 批量移出：两条都回未归类，两块板都空
        let batchCleared = [a.id, b.id].reduce(into: 0) {
            if db.moveItemToBoard(itemID: $1, boardID: nil) { $0 += 1 }
        }
        assertEqual(batchCleared, 2, "批量移出两条都命中")
        assertEqual(db.fetchClipboardItems(boardID: work.id).isEmpty, true, "原板已空")
        assertEqual(db.fetchClipboardItems(boardID: later.id).isEmpty, true, "改投过的板也空")
        assertEqual(db.fetchClipboardItem(id: a.id)?.boardID == nil, true, "移出后 board_id 为 NULL")
        assertEqual(db.clipboardItemCount(), 3, "移板不增删条目")

        print("✅ 剪贴板批量移入板 / 改投 / 批量移出 works")
    }
}

