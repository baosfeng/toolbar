import Foundation

// MARK: - 文档级来源的发现与扫描（Gemini CLI）

/// 文档级来源的读取模型 —— 一个文件**整体**交给解析器，不按行喂
///
/// Gemini CLI 的落盘有两条形态（新版逐行 JSONL / 旧版整份 JSON），解析器的
/// `parse(contentsOf:)` 自己先试整体解析、失败再逐行，所以调用方只需把整个文件给它，
/// **不要**接 `HarnessPlainLineReader` 逐行喂（那样旧版整份 JSON 会被切碎，一行都不是合法 JSON）。
///
/// 一个文件内可能有多会话（按 `sessionId` 分组）：发现阶段解析一次拿到会话键，
/// 每个会话落成一个扫描单元 `<filePath>#<sessionKey>`；扫描阶段按单元键取该会话的事件。
/// 同一文件的多会话共用文件的 (size, mtime) 作增量判据 —— 文件变了全部单元重扫。
public final class HarnessDocumentSourceReader: @unchecked Sendable {

    private let lock = NSLock()
    /// 文件路径 → (会话键 → 扫描单元)
    private var unitsByFile: [String: [String: TokenSourceSessionUnit]] = [:]

    public init() {}

    /// 新一轮发现开始：丢掉上一轮的文件缓存（文件可能被追加或删除）
    public func beginRound() {
        lock.lock()
        unitsByFile.removeAll()
        lock.unlock()
    }

    // MARK: - 候选文件

    /// 该来源的候选会话文件（`.jsonl` / `.json`，文件名以 `session` 开头）
    ///
    /// 同名的第二份（旧桶名是 project root 的 sha256，迁移会把同一会话复制到新桶）只取先出现的
    /// 那一份，另一份计入 dropped —— 静默丢弃会让「为什么少了一个会话」无从查起。
    public static func candidates(
        roots: [URL],
        fileManager: FileManager = .default
    ) -> (files: [URL], dropped: Int) {
        var files: [URL] = []
        var dropped = 0
        var seenNames = Set<String>()
        for root in roots {
            for url in sessionFiles(under: root, maxDepth: 6, fileManager: fileManager) {
                guard seenNames.insert(url.lastPathComponent).inserted else {
                    dropped += 1
                    continue
                }
                files.append(url)
            }
        }
        return (files.sorted { $0.path < $1.path }, dropped)
    }

    // MARK: - 发现

    /// 发现该来源的全部会话扫描单元（每个文件解析一次，按会话键拆单元）
    public func discover(source: TokenSourceID, roots: [URL], fileManager: FileManager = .default)
        -> (files: [HarnessSessionFile], droppedDuplicates: Int) {
        let candidates = Self.candidates(roots: roots, fileManager: fileManager)
        var files: [HarnessSessionFile] = []
        for url in candidates.files {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let mtimeMs = Int64(((attributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? 0) * 1000)
            let units = loadUnits(url: url, source: source)
            for unit in units {
                files.append(HarnessSessionFile(
                    path: unit.path, sessionID: unit.sessionKey, size: size, mtimeMs: mtimeMs,
                    members: [url.path], source: source))
            }
        }
        return (files, candidates.dropped)
    }

    // MARK: - 扫描

    /// 扫描一个单元：缓存命中直接用；未命中就重新解析该文件再取
    public func scan(file: HarnessSessionFile) -> HarnessSessionScanResult {
        let path = file.members.first ?? file.path
        if let units = cachedUnits(path: path), let unit = units[file.sessionID] {
            return unit.scanResult
        }
        let units = loadUnits(url: URL(fileURLWithPath: path), source: file.source)
        let unit = units.first { $0.sessionKey == file.sessionID }
            ?? TokenSourceSessionUnit(path: file.path, sessionKey: file.sessionID,
                                      source: file.source, events: [], cwd: "",
                                      malformedCount: 1, ignoredCount: 0)
        return unit.scanResult
    }

    // MARK: - 内部

    /// 解析一个文件 → 会话单元（读不出来给一个坏记录单元，让失败可见而不是静默 0）
    private func loadUnits(url: URL, source: TokenSourceID) -> [TokenSourceSessionUnit] {
        let fallback = url.deletingPathExtension().lastPathComponent
        let units: [TokenSourceSessionUnit]
        if let report = GeminiSessionParser.parse(contentsOf: url) {
            units = TokenSourceSessionUnits.units(from: report, pathPrefix: url.path,
                                                 fallbackSessionKey: fallback)
        } else {
            units = [TokenSourceSessionUnit(
                path: TokenSourceSessionUnits.scanPath(prefix: url.path, sessionKey: fallback),
                sessionKey: fallback, source: source, events: [], cwd: "",
                malformedCount: 1, ignoredCount: 0)]
        }
        var indexed: [String: TokenSourceSessionUnit] = [:]
        for unit in units where indexed[unit.sessionKey] == nil { indexed[unit.sessionKey] = unit }
        lock.lock()
        unitsByFile[url.path] = indexed
        lock.unlock()
        return units
    }

    private func cachedUnits(path: String) -> [String: TokenSourceSessionUnit]? {
        lock.lock()
        defer { lock.unlock() }
        return unitsByFile[path]
    }

    /// 递归收集 `session*.jsonl` / `session*.json`（跳过隐藏项；深度上限防误扫）
    private static func sessionFiles(
        under root: URL,
        maxDepth: Int,
        fileManager: FileManager
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            guard name.hasPrefix("session"),
                  url.pathExtension == "jsonl" || url.pathExtension == "json" else { continue }
            result.append(url)
        }
        return result
    }
}
