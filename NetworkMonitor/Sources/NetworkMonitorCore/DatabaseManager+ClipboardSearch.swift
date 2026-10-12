import Foundation
import SQLite3

// MARK: - LIKE 模式转义（全文检索共用）

/// LIKE 模式转义与拼装（纯函数，公开供仓储与测试共用）
///
/// 单遍逐字符处理：命中 `\` / `%` / `_` 时先补一个反斜杠再输出原字符，
/// 因此不会出现「先替换 % 再替换 \」造成的二次转义，结果可直接与 `ESCAPE '\'` 配对使用。
public enum ClipboardLIKEPattern {

    /// 转义 LIKE 元字符：`\` → `\\`、`%` → `\%`、`_` → `\_`
    /// - Parameter value: 原始查询串
    /// - Returns: 转义后的字面串（不含两侧通配符）
    public static func escape(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }

    /// 包含匹配模式：`%` + 转义后的查询串 + `%`
    public static func contains(_ value: String) -> String {
        "%\(escape(value))%"
    }
}

extension DatabaseManager {

    // MARK: - 全文检索

    public func searchClipboardItems(query: String, limit: Int) -> [ClipboardItem] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, limit > 0 else { return [] }
        // 元字符一律转义后按字面匹配；clamping 兜住 Int.max 等极大 limit，避免 Int32 溢出陷阱
        let pattern = ClipboardLIKEPattern.contains(keyword)
        let capped = Int32(clamping: limit)
        // SQLITE_TRANSIENT：让 SQLite 立即复制绑定文本，避免临时字符串生命周期不确定；
        // 用局部量而非全局常量，避免非 Sendable 的 C 函数指针触发 Swift 6 并发检查
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        return serialQueue.sync { () -> [ClipboardItem] in
            guard let db else { return [] }
            // COALESCE 归一 NULL：text / source_app_name 可为 NULL，
            // 直接比较会得到 NULL 参与三值逻辑，这里显式等价于「该列为空 → 不命中」
            let sql = """
            SELECT \(ClipboardSchema.columns) FROM clipboard_items
            WHERE (COALESCE(text, '') LIKE ? ESCAPE '\\'
                OR preview LIKE ? ESCAPE '\\'
                OR COALESCE(source_app_name, '') LIKE ? ESCAPE '\\')
            ORDER BY is_pinned DESC, created_at DESC LIMIT ?;
            """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                logger.warning("剪贴板全文检索准备失败: \(String(cString: sqlite3_errmsg(db)))")
                return []
            }
            for index in Int32(1)...Int32(3) {
                pattern.withCString { sqlite3_bind_text(stmt, index, $0, -1, transient) }
            }
            sqlite3_bind_int(stmt, 4, capped)
            return clipItems(from: stmt)
        }
    }
}
