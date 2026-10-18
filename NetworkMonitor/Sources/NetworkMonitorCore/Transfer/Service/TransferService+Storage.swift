import Foundation

// MARK: - 接收目录与记录清理

/// 说明：与主文件同属 `TransferService`，成员可见性放宽为 internal 以便跨文件调用。
extension TransferService {


    /// 收件目录（设置窗展示路径）
    public nonisolated var receiveDirectory: URL { configuration.receiveDirectory }

    /// 接收目录占用（文件数与总字节）
    public nonisolated func receiveDirectorySummary() -> ReceiveDirectoryStats.Summary {
        ReceiveDirectoryStats.scan(directory: configuration.receiveDirectory)
    }

    /// 清空接收目录并移除已终结的接收会话记录
    ///
    /// 进行中的会话其 `.part` 也会被删除，对应传输会因文件消失而失败——这是用户主动清理的预期结果。
    @discardableResult
    public func clearReceivedFiles() -> (removedFiles: Int, removedBytes: Int64) {
        let summary = receiveDirectorySummary()
        for url in ReceiveDirectoryStats.files(in: configuration.receiveDirectory) {
            try? FileManager.default.removeItem(at: url)
        }
        let terminalReceiveIds = contexts
            .filter { $0.value.session.direction == .recv && $0.value.session.state.isTerminal }
            .map(\.key)
        for sessionId in terminalReceiveIds { contexts[sessionId] = nil }
        notifySessions()
        logger.info("已清理接收目录：\(summary.fileCount) 个文件，共 \(formatBytesFull(UInt64(summary.totalBytes)))")
        return (summary.fileCount, summary.totalBytes)
    }

}
