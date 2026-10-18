import Foundation

// MARK: - 观察者与配对查询

/// 说明：与主文件同属 `TransferService`，成员可见性放宽为 internal 以便跨文件调用。
extension TransferService {


    /// 订阅会话列表变化（回调投递到 `observerQueue`）
    public func observeSessions(_ handler: @escaping @Sendable ([TransferSession]) -> Void) {
        onSessionsChanged = handler
        notifySessions()
    }

    /// 订阅会话结束事件（完成 / 失败 / 取消，用于通知与音效）
    public func observeSessionFinished(_ handler: @escaping @Sendable (TransferSession) -> Void) {
        onSessionFinished = handler
    }

    /// 当前会话快照（按创建时间倒序）
    public func sessionSnapshot() -> [TransferSession] {
        contexts.values.map(\.session).sorted { $0.createdAt > $1.createdAt }
    }

    /// 取单个会话
    public func session(id: String) -> TransferSession? {
        contexts[id]?.session
    }

    /// 设备列表快照（UI 直接读）
    public nonisolated func deviceSnapshot() -> [RemoteDevice] {
        registry.snapshot()
    }

    /// 配对状态
    public func isPaired(deviceId: String) -> Bool {
        pairing.isPaired(deviceId)
    }

    /// 移除配对记忆（回到 PIN 流程）
    public func removePairing(deviceId: String) {
        pairing.remove(deviceId: deviceId)
        registry.setPaired(false, deviceId: deviceId)
        logger.info("已移除设备 \(deviceId) 的配对记忆")
    }

    /// 从任务列表移除一条**已终结**的会话（进行中的会话不允许移除）
    /// - Parameter deleteFiles: 为 true 时一并删除接收方向已落盘的文件
    /// - Returns: 是否移除成功
    @discardableResult
    public func dismissSession(id: String, deleteFiles: Bool) -> Bool {
        guard let context = contexts[id], context.session.state.isTerminal else { return false }
        if deleteFiles, context.session.direction == .recv, let directory = context.session.directory {
            for file in context.session.files {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file.name))
            }
        }
        contexts[id] = nil
        notifySessions()
        logger.info("已移除任务 \(id)（删除文件：\(deleteFiles)）")
        return true
    }

}
