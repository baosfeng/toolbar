import Foundation

// MARK: - 会话文件描述

/// 会话文件（发现阶段的产物 + 增量判定依据）
public struct HarnessSessionFile: Sendable, Equatable {
    /// 会话标识路径：会话目录绝对路径（多版本文件的合并单元）
    public let path: String
    /// 会话 ID（会话目录名）
    public let sessionID: String
    /// 该会话全部版本文件字节数合计（增量判定）
    public let size: Int64
    /// 该会话全部版本文件中最新的修改时间毫秒（增量判定）
    public let mtimeMs: Int64
    /// 参与合并扫描的版本文件绝对路径（空表示仅 path 自身）
    public let members: [String]

    public init(path: String, sessionID: String, size: Int64, mtimeMs: Int64, members: [String] = []) {
        self.path = path
        self.sessionID = sessionID
        self.size = size
        self.mtimeMs = mtimeMs
        self.members = members
    }
}

// MARK: - 扫描记录

/// 已扫描会话记录（落 harness_session_scan 表）
public struct HarnessSessionScanRecord: Sendable, Equatable {
    public let path: String
    public let sessionID: String
    public let size: Int64
    public let mtimeMs: Int64
    /// 扫描完成时间（Unix 秒）
    public let scannedAt: Double

    public init(path: String, sessionID: String, size: Int64, mtimeMs: Int64, scannedAt: Double) {
        self.path = path
        self.sessionID = sessionID
        self.size = size
        self.mtimeMs = mtimeMs
        self.scannedAt = scannedAt
    }

    /// 由文件描述与扫描时间构造
    public init(file: HarnessSessionFile, scannedAt: Double) {
        self.init(
            path: file.path,
            sessionID: file.sessionID,
            size: file.size,
            mtimeMs: file.mtimeMs,
            scannedAt: scannedAt
        )
    }

    /// 文件是否与本次记录一致（size 与 mtime 都相同即视为未变更）
    public func matches(size: Int64, mtimeMs: Int64) -> Bool {
        self.size == size && self.mtimeMs == mtimeMs
    }
}

// MARK: - 用量事件

/// 单条 usage 事件（落 harness_token_event 表）
public struct HarnessTokenEvent: Sendable, Equatable {
    public let sessionID: String
    public let cwd: String
    public let provider: String
    public let model: String
    /// 事件时间（Unix 毫秒）
    public let tsMs: Int64
    public let usage: HarnessTokenUsage

    public init(sessionID: String, cwd: String, provider: String, model: String, tsMs: Int64, usage: HarnessTokenUsage) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.provider = provider
        self.model = model
        self.tsMs = tsMs
        self.usage = usage
    }
}
