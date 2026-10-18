import Foundation

// MARK: - 文件名去重

/// 文件名解析 — 收件落盘名在 `accept` 阶段一次确定，避免中途改名
///
/// 规则（设计文档 §5）：
/// - 同名文件追加 ` (1)`、` (2)`…，扩展名保留在末尾
/// - 收到的名字先做安全清洗：去掉路径分隔符与 `..`，空名回落为「未命名」
public enum FileNameResolver {

    /// 清洗外部传入的文件名（防路径穿越、控制字符）
    public static func sanitize(_ rawName: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未命名" }
        // 只保留最后一段路径，避免 `../../etc/passwd` 这类名字
        let lastComponent = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        guard var name = lastComponent, !name.isEmpty else { return "未命名" }
        name = name.replacingOccurrences(of: "..", with: "_")
        // 去掉控制字符（U+0000–U+001F、U+007F）
        name = String(name.unicodeScalars.filter { scalar in
            !(scalar.value < 0x20 || scalar.value == 0x7F)
        })
        if name.isEmpty || name == "." {
            return "未命名"
        }
        return name
    }

    /// 生成不与 `existing` 冲突的名字
    ///
    /// - Parameters:
    ///   - name: 已清洗的期望文件名
    ///   - existing: 已占用的文件名集合
    /// - Returns: `照片.jpg` → 首次返回原名；再次返回 `照片 (1).jpg`、`照片 (2).jpg`…
    public static func uniqueName(for name: String, in existing: Set<String>) -> String {
        let sanitized = sanitize(name)
        guard existing.contains(sanitized) else { return sanitized }

        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var index = 1
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
    }

    /// 从目录现有文件生成占用集合
    public static func existingNames(in directory: URL) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(contents)
    }
}

// MARK: - offset 校验

/// 上传偏移校验 — `PUT /upload` 的 `offset` 必须与已收字节一致（否则 4003）
public enum UploadPlanner {

    /// 校验请求偏移
    ///
    /// - Parameters:
    ///   - requested: 客户端声明的起始偏移
    ///   - received: 接收端 `.part` 已有字节数
    /// - Throws: `offsetMismatch`（code 4003）
    public static func validateOffset(requested: Int64, received: Int64) throws {
        guard requested >= 0 else {
            throw TransferError.offsetMismatch(expected: received, received: requested)
        }
        // 从头重传（requested == 0）允许，调用方会以该偏移截断 `.part` 后覆盖写；
        // 中间偏移必须严格等于已收字节，否则数据会错位。
        if requested == received || requested == 0 { return }
        throw TransferError.offsetMismatch(expected: received, received: requested)
    }

    /// 续传起点：`.part` 大小落在 `0…size` 内才可续传，超过预期大小一律从头开始
    public static func resumableOffset(partSize: Int64, expectedSize: Int64) -> Int64 {
        guard partSize > 0, partSize <= expectedSize else { return 0 }
        return partSize
    }

    /// 重试偏移：服务端已收字节优先，取不到时才回落到本地记录
    ///
    /// 接收端对 `offset` 是严格校验（与本端 `validateOffset`、Android `TransferEngine` 一致），
    /// 因此断网重试必须用服务端确认过的偏移，不能假设可以从头覆盖。
    public static func retryOffset(serverReported: Int64?, fallback: Int64) -> Int64 {
        guard let serverReported, serverReported >= 0 else { return max(0, fallback) }
        return serverReported
    }

    /// 接收端 `.part` 路径（与 `FileStreamWriter` 保持一致）
    public static func partURL(for finalURL: URL) -> URL {
        finalURL.appendingPathExtension("part")
    }
}
