import Foundation

// MARK: - 截图保存目录偏好

/// 快速保存目录偏好 — 键名、读写与解析集中在这里，避免字符串散落
///
/// 偏好只存「自定义目录的绝对路径」：未设置 = 沿用 `SnipFileNaming.quickSaveDirectory()`。
/// 解析结果只对之后的落盘生效，切换不会迁移已保存的文件。
public enum SnipSaveDirectory {

    /// 存储键：自定义快速保存目录（缺省表示使用默认目录）
    public static let key = "snip.quickSaveDirectoryPath"

    /// 当前自定义路径（未自定义或值为空白时为 nil）
    public static func customPath(storage: any KeyValueStorage) -> String? {
        guard let stored = storage.string(forKey: key) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 写入自定义目录；传 nil 表示恢复默认
    public static func setCustomDirectory(_ url: URL?, storage: any KeyValueStorage) {
        guard let url else {
            storage.removeObject(forKey: key)
            return
        }
        storage.set(url.standardizedFileURL.path, forKey: key)
    }

    /// 解析实际使用的目录：自定义优先，否则回落到默认目录
    public static func resolvedQuickSaveDirectory(
        storage: any KeyValueStorage,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let path = customPath(storage: storage) else {
            return SnipFileNaming.quickSaveDirectory(homeDirectory: homeDirectory)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
