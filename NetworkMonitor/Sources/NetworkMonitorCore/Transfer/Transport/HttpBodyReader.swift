import Foundation
import Network

// MARK: - 请求体读取器

/// 流式请求体读取器 — 上传时边收边交给业务落盘，内存占用与文件大小无关
///
/// 背压模型：消费方调用 `next()` 后才触发一次底层 `receive`，
/// 未消费时不会继续从内核读取，因此不会出现「读取速度远超落盘速度」导致的内存堆积。
/// 每连接只处理一个请求：读到 `Content-Length` 即结束，多余字节丢弃。
public final class HttpBodyReader: @unchecked Sendable {

    private let lock = NSLock()
    private let connection: NWConnection
    private var remaining: Int64
    private var buffered: [Data] = []
    private var waiter: CheckedContinuation<Data?, Never>?
    private var finished: Bool
    private var requesting = false
    private var receivedTotal: Int64 = 0

    /// - Parameters:
    ///   - connection: 底层连接（读取器自行驱动 receive）
    ///   - remaining: `Content-Length` 剩余字节
    ///   - preloaded: 解析头部时已多读到的 body 片段
    public init(connection: NWConnection, remaining: Int64, preloaded: Data) {
        self.connection = connection
        self.remaining = max(0, remaining)
        self.finished = remaining <= 0
        if !preloaded.isEmpty, remaining > 0 {
            let clipped = Data(preloaded.prefix(Int(min(Int64(preloaded.count), remaining))))
            buffered = [clipped]
            self.remaining -= Int64(clipped.count)
            receivedTotal += Int64(clipped.count)
            if self.remaining <= 0 { finished = true }
        }
    }

    /// 已收到的字节总数
    public var receivedBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return receivedTotal
    }

    /// 字节是否已全部收完
    public var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished && buffered.isEmpty
    }

    /// 取下 64 KiB 块；全部读完返回 nil
    public func next() async -> Data? {
        switch pollNext() {
        case .chunk(let data):
            return data
        case .finished:
            return nil
        case .wait:
            break
        }
        // 闭包是同步上下文，锁操作收敛在 attachWaiter 内
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let shouldFetch = attachWaiter(continuation)
            if shouldFetch { fetchMore() }
        }
    }

    // MARK: - 内部

    /// 立即取一块 / 判断结束 / 需要挂起（锁操作在此同步函数内完成）
    private enum NextState {
        case chunk(Data)
        case finished
        case wait
    }

    private func pollNext() -> NextState {
        lock.lock()
        defer { lock.unlock() }
        if !buffered.isEmpty { return .chunk(buffered.removeFirst()) }
        if finished { return .finished }
        return .wait
    }

    /// 登记等待者；返回 true 表示需要发起一次底层 receive
    private func attachWaiter(_ continuation: CheckedContinuation<Data?, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        waiter = continuation
        let shouldFetch = !requesting
        if shouldFetch { requesting = true }
        return shouldFetch
    }

    /// 主动结束（会话取消 / 连接断开时由服务端调用）
    public func cancel() {
        connection.cancel()
        finish()
    }

    private func fetchMore() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: TransferProtocol.chunkSize) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.push(data) }
            if isComplete || error != nil { self.finish() }
        }
    }

    private func push(_ data: Data) {
        lock.lock()
        requesting = false
        guard !finished else {
            lock.unlock()
            return
        }
        var chunk = data
        if Int64(chunk.count) >= remaining {
            chunk = Data(chunk.prefix(Int(remaining)))
            remaining = 0
            finished = true
        } else {
            remaining -= Int64(chunk.count)
        }
        receivedTotal += Int64(chunk.count)

        if let waiting = waiter {
            waiter = nil
            lock.unlock()
            waiting.resume(returning: chunk.isEmpty ? nil : chunk)
        } else {
            buffered.append(chunk)
            lock.unlock()
        }
    }

    private func finish() {
        lock.lock()
        finished = true
        requesting = false
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume(returning: nil)
    }
}
