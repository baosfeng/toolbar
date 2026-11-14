import Foundation

// MARK: - 剪贴板图片存储占用统计

/// 剪贴板图片目录的占用统计 —— 不依赖 AppKit，只读文件系统
///
/// 口径（设置页「存储」卡）：
/// - 只统计目录**第一层的普通文件**：原图与缩略图都平铺在图片目录下，子目录既不递归也不计入；
/// - 目录不存在或不可读 → `exists = false`，条数与字节均为 0，不抛错、不写错误日志；
/// - 单个文件读不到属性（权限 / 竞态删除）时跳过该文件，其余照常统计，不让整次统计失败。
public enum ClipboardStorageUsage {

    /// 一次统计的结果
    public struct Summary: Equatable, Sendable {
        /// 文件条数（只含第一层普通文件）
        public let fileCount: Int
        /// 文件总字节
        public let byteCount: UInt64
        /// 目录是否存在且可读（false 时前两项恒为 0）
        public let exists: Bool

        public init(fileCount: Int, byteCount: UInt64, exists: Bool) {
            self.fileCount = fileCount
            self.byteCount = byteCount
            self.exists = exists
        }
    }

    /// 目录不存在 / 不可读时的空结果
    public static let empty = Summary(fileCount: 0, byteCount: 0, exists: false)

    /// 统计目录占用
    /// - Parameter directory: 待统计目录（剪贴板图片落盘目录）
    /// - Returns: 条数 / 字节 / 目录是否存在；任何失败都落到 `empty`，不向上抛
    public static func summarize(in directory: URL) -> Summary {
        // contentsOfDirectory 对「路径不存在」「是文件而非目录」「无读权限」都返回 nil，一并当作目录不可用
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return empty
        }
        var fileCount = 0
        var byteCount: UInt64 = 0
        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize, size >= 0 else { continue }
            fileCount += 1
            byteCount += UInt64(size)
        }
        return Summary(fileCount: fileCount, byteCount: byteCount, exists: true)
    }
}
