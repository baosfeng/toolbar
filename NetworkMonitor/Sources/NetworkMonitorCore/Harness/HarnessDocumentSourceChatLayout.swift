import Foundation

// MARK: - 文档级来源（Gemini CLI）的目录结构发现

/// 会话文件在桶里的位置
///
/// Gemini CLI 的会话落在 `<桶>/chats/` 下，子 agent 再进一级：
/// - 父会话：`chats/session-<UTC 截到分钟>-<id 前 8 位>.jsonl`（旧版是 `session-*.json` 整份 JSON）；
/// - 子 agent：`chats/<parentId>/<sessionId>.jsonl` —— **文件名没有 `session` 前缀**。
///
/// 所以归属只能按目录结构判：按文件名前缀判会把整类子 agent 会话漏掉（有数据但统计不到）。
public enum HarnessDocumentChatPlacement: String, Sendable, Equatable {
    /// `chats` 下的直接子文件（父会话；新版逐行 JSONL / 旧版整份 JSON）
    case parentSession
    /// `chats/<parentId>/` 下的文件（子 agent；递归一层）
    case subAgent
}

/// 一个候选会话文件（发现阶段产物：路径 + 归属，不含内容）
public struct HarnessDocumentChatFile: Sendable, Equatable {
    public let url: URL
    public let placement: HarnessDocumentChatPlacement

    public init(url: URL, placement: HarnessDocumentChatPlacement) {
        self.url = url
        self.placement = placement
    }
}

/// 一个桶的收数统计（诊断用：桶名不是固定格式，只能逐桶报出来才看得出漏在哪）
public struct HarnessDocumentBucketReport: Sendable, Equatable {
    /// 桶名（相对发现根的路径，如 `slug`；根选到 `.gemini` 时为 `tmp/slug`）
    public let name: String
    /// 收下的父会话文件数
    public let parentSessionFiles: Int
    /// 收下的子 agent 文件数
    public let subAgentFiles: Int

    public init(name: String, parentSessionFiles: Int, subAgentFiles: Int) {
        self.name = name
        self.parentSessionFiles = parentSessionFiles
        self.subAgentFiles = subAgentFiles
    }

    public var total: Int { parentSessionFiles + subAgentFiles }

    /// 一桶一行，便于日志 / 诊断文本直接拼接
    public var summary: String { "\(name)(父 \(parentSessionFiles) / 子 \(subAgentFiles))" }
}

/// 发现层候选结果：文件清单 + 按桶统计 + 丢弃数
///
/// `buckets` 与 `summary` 是可观测面：桶名（项目目录 slug）没有固定格式，旧桶名是
/// project root 的 sha256、迁移会整目录搬迁，只报总数看不出「哪个桶一个文件都没收到」。
public struct HarnessDocumentCandidates: Sendable, Equatable {
    public let files: [HarnessDocumentChatFile]
    public let buckets: [HarnessDocumentBucketReport]
    /// 同一绝对路径被多个根重复收到的份数（多根 / 根嵌套时会发生）
    public let droppedDuplicates: Int

    public init(files: [HarnessDocumentChatFile],
                buckets: [HarnessDocumentBucketReport],
                droppedDuplicates: Int) {
        self.files = files
        self.buckets = buckets
        self.droppedDuplicates = droppedDuplicates
    }

    public var parentSessionFileCount: Int { files.filter { $0.placement == .parentSession }.count }
    public var subAgentFileCount: Int { files.filter { $0.placement == .subAgent }.count }

    /// 一句话诊断（含按桶明细）；未收到任何文件时给出原因候选
    public var summary: String {
        if files.isEmpty {
            return "桶 0 个 / 文件 0 个：根下没有 chats 目录，或目录不可读（未使用 Gemini CLI / 目录选错层级）"
        }
        let detail = buckets.map(\.summary).joined(separator: "、")
        return "桶 \(buckets.count) 个 / 父会话 \(parentSessionFileCount) / 子 agent "
            + "\(subAgentFileCount)、丢弃重复 \(droppedDuplicates)：" + detail
    }
}

/// 文档级来源的发现结果（文件 + 丢弃数 + 按桶统计）
///
/// 刻意保留 `files` / `droppedDuplicates` 两个成员名：调用方（`HarnessSourceDiscovery`）
/// 只换类型、不改取用方式。
public struct HarnessDocumentDiscoverResult: Sendable, Equatable {
    public let files: [HarnessSessionFile]
    public let droppedDuplicates: Int
    public let buckets: [HarnessDocumentBucketReport]
    public let summary: String

    public init(files: [HarnessSessionFile],
                droppedDuplicates: Int,
                buckets: [HarnessDocumentBucketReport],
                summary: String) {
        self.files = files
        self.droppedDuplicates = droppedDuplicates
        self.buckets = buckets
        self.summary = summary
    }
}

/// 目录结构发现：找出全部 `chats` 目录 → 按归属收文件（只读布局与扩展名，不读内容）
///
/// 三条硬规则（都来自实测目录树，不是猜测）：
/// 1. **桶名不做任何假设**：桶是项目 registry 的短 id（项目目录 slug，冲突加 `-N`），旧桶名是
///    project root 的 sha256、迁移会整目录搬迁 —— 所以逐个桶都扫，绝不用桶名拼路径；
/// 2. **不按文件名前缀判归属**：父会话与子 agent 的区别在目录层级，不在文件名；
/// 3. **文件名不参与时间解析**：`session-<UTC 截到分钟>[-<冲突序号>].jsonl` 是分钟精度、可能带
///    序号，段数不固定 —— 发现层只当它是「一个文件」，文件时间一律取磁盘 mtime。
public enum HarnessDocumentChatLayout {

    /// 会话子目录名（Gemini CLI 落盘固定用它）
    public static let chatsDirectoryName = "chats"

    /// 搜索深度上限：`root/tmp/<桶>/chats` 已到 3 层，再深属异常结构
    private static let maxDepth = 4

    /// 发现全部候选文件（按绝对路径去重；排序固定，便于断言与日志对比）
    ///
    /// 去重键是**绝对路径**：旧实现按 `lastPathComponent` 去重，两个桶里同名的
    /// `session-<时间>-<id>.jsonl` 会被误判成重复而丢掉一份。
    public static func candidates(
        roots: [URL],
        fileManager: FileManager = .default
    ) -> HarnessDocumentCandidates {
        var files: [HarnessDocumentChatFile] = []
        var buckets: [HarnessDocumentBucketReport] = []
        var seenPaths = Set<String>()
        var dropped = 0
        for root in roots {
            for chatsDirectory in chatDirectories(under: root, fileManager: fileManager) {
                let (parents, subAgents) = scan(chatsDirectory: chatsDirectory, fileManager: fileManager)
                var keptParents = 0
                var keptSubAgents = 0
                for file in parents + subAgents {
                    guard seenPaths.insert(file.url.standardizedFileURL.path).inserted else {
                        dropped += 1
                        continue
                    }
                    files.append(file)
                    if file.placement == .parentSession { keptParents += 1 } else { keptSubAgents += 1 }
                }
                buckets.append(HarnessDocumentBucketReport(
                    name: bucketName(chatsDirectory: chatsDirectory, root: root),
                    parentSessionFiles: keptParents,
                    subAgentFiles: keptSubAgents))
            }
        }
        files.sort { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }
        return HarnessDocumentCandidates(files: files, buckets: buckets, droppedDuplicates: dropped)
    }

    // MARK: - 找 chats 目录

    /// 递归找出根下全部 `chats` 目录（含根自身就是 chats 的情形）
    ///
    /// 找不到时再看根自己是否直接装着会话文件（用户把自定义目录选到了 `chats` 的上一层或
    /// 拷出来的目录）：这时把根当 chats 处理，宁可多收也不静默漏掉。
    private static func chatDirectories(under root: URL, fileManager: FileManager) -> [URL] {
        var result: [URL] = []
        if root.lastPathComponent == chatsDirectoryName { result.append(root) }
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard url.lastPathComponent == chatsDirectoryName, isDirectory(url, fileManager: fileManager)
            else { continue }
            if url.standardizedFileURL != root.standardizedFileURL { result.append(url) }
            // chats 之下不再找 chats（子 agent 那一层是 chats/<parentId>，没有更深的结构）
            enumerator.skipDescendants()
        }
        if result.isEmpty, containsSessionDocuments(root, fileManager: fileManager) {
            result.append(root)
        }
        return result
    }

    /// 根下直接有没有会话文件（只读一层：用于识别「自定义目录选到了 chats 本身」）
    private static func containsSessionDocuments(_ directory: URL, fileManager: FileManager) -> Bool {
        entries(of: directory, fileManager: fileManager).contains { $0.isSessionDocument }
    }

    // MARK: - 收一个 chats 目录

    /// 收一个 chats 目录：直接子文件是父会话，一级子目录里的文件是子 agent
    private static func scan(
        chatsDirectory: URL,
        fileManager: FileManager
    ) -> (parents: [HarnessDocumentChatFile], subAgents: [HarnessDocumentChatFile]) {
        var parents: [HarnessDocumentChatFile] = []
        var subAgents: [HarnessDocumentChatFile] = []
        for entry in entries(of: chatsDirectory, fileManager: fileManager) {
            guard entry.isDirectory else {
                if entry.isSessionDocument {
                    parents.append(HarnessDocumentChatFile(url: entry.url, placement: .parentSession))
                }
                continue
            }
            // 子 agent 只递归一层：chats/<parentId>/<sessionId>.jsonl
            for child in entries(of: entry.url, fileManager: fileManager)
            where child.isSessionDocument && !child.isDirectory {
                subAgents.append(HarnessDocumentChatFile(url: child.url, placement: .subAgent))
            }
        }
        return (parents, subAgents)
    }

    // MARK: - 目录工具

    /// 目录下的直接子项（读不了按空处理：半损坏的目录树不该让整轮发现失败）
    private static func entries(
        of directory: URL,
        fileManager: FileManager
    ) -> [(url: URL, isDirectory: Bool, isSessionDocument: Bool)] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            // 新版逐行 .jsonl 与旧版整份 .json 都要收（只认 .jsonl 会整类漏掉旧格式）
            let isDocument = !isDirectory.boolValue && (name.hasSuffix(".jsonl") || name.hasSuffix(".json"))
            return (url, isDirectory.boolValue, isDocument)
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return isDirectory.boolValue
    }

    /// 桶名：chats 的父目录相对发现根的路径（根选错层级时也能看出是哪一段）
    private static func bucketName(chatsDirectory: URL, root: URL) -> String {
        let parent = chatsDirectory.deletingLastPathComponent()
        let parentPath = parent.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if parentPath.hasPrefix(prefix) {
            let relative = String(parentPath.dropFirst(prefix.count))
            return relative.isEmpty ? parent.lastPathComponent : relative
        }
        return parent.lastPathComponent
    }
}
