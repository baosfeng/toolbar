import Foundation

// MARK: - 传送页状态带签名

/// 传送页页脚状态带的内容签名（纯函数，便于 TestRunner 断言）
///
/// 覆盖状态带的全部可见项：发现状态 / 设备数 / 任务数 / 进行中 / 免配对倒计时。
/// 用途：内容没变就不重建状态带——旧实现每秒 clear + 重建 5 个条目（15 个视图），
/// 是主线程 Auto Layout 与文本测量热点的触发源（见 docs/调研/性能剖析-CPU与内存.md）。
public enum TransferBandSignature {

    /// 生成签名；任一可见项变化则签名变化
    public static func make(statusText: String,
                            deviceCount: Int,
                            sessionCount: Int,
                            activeCount: Int,
                            autoAcceptText: String) -> String {
        // 用不会出现在文案里的分隔符，避免「值里带分隔符恰好拼出另一组值」的伪相等
        let separator = String(UnicodeScalar(0x1F)!)
        return [statusText,
                String(deviceCount),
                String(sessionCount),
                String(activeCount),
                autoAcceptText].joined(separator: separator)
    }
}
