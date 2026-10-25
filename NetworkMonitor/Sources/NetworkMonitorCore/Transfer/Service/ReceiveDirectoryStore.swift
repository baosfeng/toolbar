import Foundation

// MARK: - 接收目录存储

/// 接收目录存储 — actor 内外共享的线程安全目录持有者
///
/// 目录原本是 `TransferService.Configuration` 里的不可变字段，服务内多处读取，
/// 设置页还要在 actor 之外同步展示路径。运行时切换目录需要一个可写且线程安全的持有者：
/// 写入只发生在 actor 的受控方法（`setReceiveDirectory(_:)`）里，读取随时可进行，
/// 因此用一把锁保护而非把读点全部改成 async。
public final class ReceiveDirectoryStore: @unchecked Sendable {

    private let lock = NSLock()
    private var directory: URL

    public init(_ directory: URL) {
        self.directory = directory
    }

    /// 当前接收目录
    public var current: URL {
        lock.lock()
        defer { lock.unlock() }
        return directory
    }

    /// 更新目录（调用方负责确保目录已存在）
    public func update(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        directory = url
    }
}
