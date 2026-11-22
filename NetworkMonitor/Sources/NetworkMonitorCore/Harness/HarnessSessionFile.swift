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
    /// 该会话文件所属来源（多来源共用一套索引表与一套扫描流水线）
    ///
    /// 带默认值 .dsh：既有 DSH 扫描器、测试桩与旧调用点都不用改。
    public let source: TokenSourceID

    public init(path: String, sessionID: String, size: Int64, mtimeMs: Int64,
                members: [String] = [], source: TokenSourceID = .dsh) {
        self.path = path
        self.sessionID = sessionID
        self.size = size
        self.mtimeMs = mtimeMs
        self.members = members
        self.source = source
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
    /// 来源（与事件的 source 一致，清理 / 重扫据此只针对一个来源）
    public let source: TokenSourceID

    public init(path: String, sessionID: String, size: Int64, mtimeMs: Int64, scannedAt: Double,
                source: TokenSourceID = .dsh) {
        self.path = path
        self.sessionID = sessionID
        self.size = size
        self.mtimeMs = mtimeMs
        self.scannedAt = scannedAt
        self.source = source
    }

    /// 由文件描述与扫描时间构造（来源跟着文件走，不在调用点再传一遍）
    public init(file: HarnessSessionFile, scannedAt: Double) {
        self.init(
            path: file.path,
            sessionID: file.sessionID,
            size: file.size,
            mtimeMs: file.mtimeMs,
            scannedAt: scannedAt,
            source: file.source
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
    /// 来源（落 harness_token_event.source；缺省 .dsh 与老数据口径一致）
    public let source: TokenSourceID

    public init(sessionID: String, cwd: String, provider: String, model: String, tsMs: Int64,
                usage: HarnessTokenUsage, source: TokenSourceID = .dsh) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.provider = provider
        self.model = model
        self.tsMs = tsMs
        self.usage = usage
        self.source = source
    }
}
