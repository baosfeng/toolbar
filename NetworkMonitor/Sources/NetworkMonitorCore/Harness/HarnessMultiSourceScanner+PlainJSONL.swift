import Foundation

// MARK: - 明文 JSONL 扫描（Claude Code / Codex）

extension HarnessMultiSourceScanner {

    /// 明文 JSONL：一个单元可含多个文件（当前两家都是单文件），逐个喂给同一个解析器
    ///
    /// 会话键取解析器给的行内会话键（Claude 的 sessionId / Codex 的 session_meta.id），
    /// 取不到才回落文件名 —— 按真会话 id 落库，项目维度的 COUNT(DISTINCT session_id) 才准。
    func scanPlain(
        file: HarnessSessionFile,
        parser: any TokenLineParsing,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult {
        parser.reset()
        var usages: [TokenSourceUsageEvent] = []
        var cwd = ""
        var sessionKey = ""
        var totalLines = 0
        let progressStride = 500
        let paths = file.members.isEmpty ? [file.path] : file.members
        for path in paths {
            try plainReader.streamLines(from: path, isCancelled: isCancelled) { line in
                totalLines += 1
                if totalLines % progressStride == 0 { onLinesRead?(totalLines) }
                autoreleasepool {
                    switch parser.parse(line: line) {
                    case .usage(let event):
                        if sessionKey.isEmpty { sessionKey = event.sessionKey }
                        if cwd.isEmpty { cwd = event.cwd }
                        usages.append(event)
                    case .session(let info):
                        if cwd.isEmpty { cwd = info.cwd }
                        if sessionKey.isEmpty { sessionKey = info.sessionKey }
                    case .ignored, .malformed:
                        break
                    }
                }
            }
        }
        onLinesRead?(totalLines)
        if isCancelled() { throw HarnessTokenError.cancellationRequested }
        let resolvedSessionID = sessionKey.isEmpty ? file.sessionID : sessionKey
        let events = usages.map { usage in
            HarnessTokenEvent(
                sessionID: resolvedSessionID,
                cwd: usage.cwd,
                provider: usage.provider,
                model: usage.model,
                tsMs: usage.tsMs,
                usage: usage.usage,
                source: file.source
            )
        }
        return HarnessSessionScanResult(
            sessionID: resolvedSessionID,
            cwd: cwd,
            events: events,
            totalLines: totalLines,
            malformedLines: parser.malformedLineCount,
            ignoredLines: parser.ignoredLineCount + parser.skippedLineCount
        )
    }
}
