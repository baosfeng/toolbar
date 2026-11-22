import Foundation

// MARK: - Codex rollout 行读取（明文 / 冷会话 zst）

/// Codex rollout 的两种落地形态：
/// - `rollout-<YYYY-MM-DDTHH-MM-SS>-<thread_id>.jsonl`：在写会话，明文；
/// - `rollout-<...>.jsonl.zst`：**mtime 超过 7 天的冷会话被上游压缩**
///   （`codex-rs/rollout/src/compression.rs`：`COMPRESSED_SUFFIX = ".zst"`、
///   `MIN_ROLLOUT_AGE = 7 * 24 * 3600`）——只读明文就会系统性漏掉旧会话。
///
/// 两条路径产出的行完全一致（都按 `\n` 切、半行留到下一块），故下游聚合口径不需要分支。
enum CodexRolloutLineReader {
    /// 解压读取器（进程内共享）
    ///
    /// 定位内置 libzstd / zstd 可执行文件只做一次：每个文件各建一份会把整轮索引拖慢。
    /// `loginShellLookup: false` —— 索引在后台队列跑，不为此起登录 shell；
    /// 包内 libzstd 与 PATH 都找不到时按「解压工具缺失」降级（与 DSH 既有降级口径一致）。
    static let zstd = HarnessZstdLineStreamer(loginShellLookup: false)

    /// 该路径是否是被压缩过的 rollout
    static func isCompressed(_ path: String) -> Bool { path.hasSuffix(".jsonl.zst") }

    /// 是否是 rollout 文件：明文 `.jsonl` 或冷会话 `.jsonl.zst`
    static func isRolloutFile(_ name: String) -> Bool {
        name.hasSuffix(".jsonl") || isCompressed(name)
    }

    /// 规范化名字：去掉 `.zst` 后即为「同一 rollout 的明文名」（两种形态共用一个去重键）
    static func canonicalName(_ name: String) -> String {
        name.hasSuffix(".zst") ? String(name.dropLast(4)) : name
    }

    /// 按路径形态取读取器：压缩 → 解压后切行；明文 → 直接切行
    static func reader(forPath path: String, plain: any HarnessLineStreaming) -> any HarnessLineStreaming {
        isCompressed(path) ? zstd : plain
    }
}
