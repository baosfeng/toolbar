import Foundation
import SQLite3

// MARK: - 列定义（列名 / SELECT 列串 / 行映射下标的唯一来源）

/// 剪贴板查询列顺序
///
/// **列名、SELECT 列串、`clipItem(from:)` 的取值下标三者由本枚举唯一决定**，改一处即三处同步。
/// 以后新增一列：① 在 `Column` 里按顺序追加一个 case；② 在 DatabaseManager+ClipboardSchema.swift
/// 的 v3 段追加一条 `ALTER TABLE clipboard_items ADD COLUMN …`；③ 把 `latestVersion` +1。
/// 列串与下标脱钩会**静默串列**（不报错、数据错位），TestRunner 有列序与逐字段回读断言守住。
public enum ClipboardSchema {

    /// 已发布的最高版本；一次迁移完成后 `PRAGMA user_version` 必等于它
    ///
    /// v3 目前只有占位段、还没有实际变更，因此仍是 2 —— 空段不推版本号。
    public static let latestVersion: Int32 = 2

    /// 列：声明顺序 = SELECT 列顺序 = 行映射下标
    public enum Column: String, CaseIterable, Sendable {
        case id, kind, text, preview
        case imagePath = "image_path"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case contentHash = "content_hash"
        case sourceBundleID = "source_bundle_id"
        case sourceAppName = "source_app_name"
        case copyCount = "copy_count"
        case isPinned = "is_pinned"
        case createdAt = "created_at"
        case pinnedAt = "pinned_at"
        case stackPosition = "stack_position"

        /// sqlite3_column_* 用的列下标（= 在 `allCases` 中的位置）
        ///
        /// 放宽为 public：TestRunner 要断言「列数 == 下标最大值 + 1、下标唯一」。
        public var index: Int32 { Self.ordinals[self] ?? 0 }

        private static let ordinals = Dictionary(
            uniqueKeysWithValues: allCases.enumerated().map { ($1, Int32($0)) }
        )
    }

    /// 列名按声明顺序排列
    public static let columnNames = Column.allCases.map(\.rawValue)

    /// SELECT 用列串（顺序与 `columnNames` 一致）
    public static let columns = columnNames.joined(separator: ", ")
}

// MARK: - 行映射（SQLite 行 → ClipboardItem）

/// 行映射专用短名
private typealias ClipColumn = ClipboardSchema.Column

/// 以下方法放宽为 internal 的原因：行映射与绑定读取辅助被同模块的
/// DatabaseManager+ClipboardRepository.swift / +ClipboardSearch.swift 复用，
/// private 会限制在单个文件内。均须在串行队列上下文内调用，命名以 clip 前缀避免冲突。
extension DatabaseManager {

    /// 绑定可空整数：nil 绑定 NULL
    func clipBindIntOrNull(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int(stmt, index, Int32(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// 读取可空整数列
    func clipIntOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(stmt, index))
    }

    /// 读取可空文本列
    func clipText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    /// 读取可空时间列（SQLite REAL 秒）
    func clipDateOrNil(_ stmt: OpaquePointer?, _ index: Int32) -> Date? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, index))
    }

    /// 行映射：关键列（id / kind / content_hash）非法时返回 nil，调用方跳过该行
    ///
    /// 下标一律走 `ClipColumn`，不再写字面量整数 —— 列序与下标同源，加列不会串位。
    func clipItem(from stmt: OpaquePointer?) -> ClipboardItem? {
        guard let stmt,
              let idText = clipText(stmt, ClipColumn.id.index),
              let id = UUID(uuidString: idText) else { return nil }
        guard let kindText = clipText(stmt, ClipColumn.kind.index) else { return nil }
        guard let kind = ClipboardItemKind(rawValue: kindText) else {
            // 未识别的 kind 会让整行静默消失（不报错、界面少一条），留一条可查证据
            logger.warning("剪贴板行 kind 无法识别（\(kindText)），跳过该行")
            return nil
        }
        guard let hash = clipText(stmt, ClipColumn.contentHash.index) else { return nil }
        return ClipboardItem(
            id: id,
            kind: kind,
            text: clipText(stmt, ClipColumn.text.index),
            preview: clipText(stmt, ClipColumn.preview.index) ?? "",
            imagePath: clipText(stmt, ClipColumn.imagePath.index),
            imageWidth: clipIntOrNil(stmt, ClipColumn.imageWidth.index),
            imageHeight: clipIntOrNil(stmt, ClipColumn.imageHeight.index),
            contentHash: hash,
            sourceBundleID: clipText(stmt, ClipColumn.sourceBundleID.index),
            sourceAppName: clipText(stmt, ClipColumn.sourceAppName.index),
            copyCount: Int(sqlite3_column_int(stmt, ClipColumn.copyCount.index)),
            isPinned: sqlite3_column_int(stmt, ClipColumn.isPinned.index) != 0,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, ClipColumn.createdAt.index)),
            pinnedAt: clipDateOrNil(stmt, ClipColumn.pinnedAt.index),
            stackPosition: clipIntOrNil(stmt, ClipColumn.stackPosition.index)
        )
    }

    /// 遍历结果集并映射（须在语句 bind 完成后调用）
    func clipItems(from stmt: OpaquePointer?) -> [ClipboardItem] {
        var items: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = clipItem(from: stmt) { items.append(item) }
        }
        return items
    }

    /// 按内容哈希回读单条（写入后取最新行）
    func clipItemByHash(_ db: OpaquePointer, _ contentHash: String) -> ClipboardItem? {
        let sql = "SELECT \(ClipboardSchema.columns) FROM clipboard_items WHERE content_hash = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.warning("剪贴板回读准备失败: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        sqlite3_bind_text_copy(stmt, 1, contentHash)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return clipItem(from: stmt)
    }
}
