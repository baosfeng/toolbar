import Foundation
import SQLite3

// MARK: - 剪贴板 schema 版本阶梯（v3 起）

/// 剪贴板表的逐级迁移段 — v3 之后的变更新增在这里
///
/// 与 v1 / v2 分开成文件：那两段是「建表 / 补版本」的历史段，长期不变；
/// 后续每次加列 / 加表都只动本文件，DatabaseManager 族不再随每次迁移增长。
extension DatabaseManager {

    // MARK: v3：图片文字识别列

    /// v3 段：`clipboard_items` 追加 `ocr_text`（图片文字的识别结果）
    ///
    /// 三态口径见 `ClipboardOCRRepository`：NULL = 未识别（唯一可调度态）、
    /// 空串 = 确认无文字、正文 = 识别结果。因此本列**不加 NOT NULL 默认值**：
    /// 老库升级后所有既有行天然是 NULL，与「新采集的图片条目」同义。
    ///
    /// 幂等：列已存在（版本被回退后重放、或表已由更新代码建好）时直接推进版本号，
    /// 不让一条 duplicate column name 把版本卡在 2、每次启动都重试一遍。
    func migrateClipboardToV3(_ db: OpaquePointer) {
        if clipColumnExists(db, table: "clipboard_items", column: ClipboardSchema.Column.ocrText.rawValue) {
            clipAdvanceVersion(db, to: 3, label: "剪贴板表结构 v3（ocr_text 已存在，仅补版本号）")
            return
        }
        let sql = "ALTER TABLE clipboard_items ADD COLUMN ocr_text TEXT;"
        guard clipExec(db, sql) else {
            logger.warning("剪贴板 v3 加列失败: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        clipAdvanceVersion(db, to: 3, label: "剪贴板表结构 v3（ocr_text）就绪")
    }

    // MARK: v4：占位段（下一位加列 / 加表在这里）

    /// v4 段：**下一位加列 / 加表在这里，勿在 v1 / v2 / v3 段里加**。
    ///
    /// 加一列的完整步骤：
    /// 1. 在 `ClipboardSchema.Column` 按顺序追加 case（列串与行映射下标随之自动同步）
    /// 2. 在本段追加一条 ALTER TABLE clipboard_items ADD COLUMN <列名> <类型>;
    /// 3. 把 `ClipboardSchema.latestVersion` +1（本段改成 to: 4 后新开 v5 段）
    /// 4. 在 TestRunner 的列序用例里补该字段的逐字段比对
    /// 放宽为 internal：版本阶梯的调度入口在 `DatabaseManager+ClipboardSchema.swift`
    func migrateClipboardToV4(_ db: OpaquePointer) {
        // 本段目前是空占位：空段不推版本号，否则老库会被标成 v4、真到 v4 时整段被跳过。
        _ = db
    }

    // MARK: 共用辅助

    /// 表里是否已有某列（ALTER 前判幂等用）
    private func clipColumnExists(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 1), String(cString: name) == column { return true }
        }
        return false
    }
}
