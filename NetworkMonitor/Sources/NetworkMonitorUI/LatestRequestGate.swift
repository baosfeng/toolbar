import Foundation

// MARK: - 最新请求闸门

/// 「只接受最新一次请求结果」的序号闸门
///
/// 用途：把主线程同步读改成异步后，慢的旧请求可能在新请求之后返回。
/// 每次发起请求取一个递增序号，回到主线程时只渲染与当前最新序号一致的结果——
/// 既不会让旧结果覆盖新数据，也不会出现「面板重开后一帧空白就再也不刷新」。
public struct LatestRequestGate: Equatable, Sendable {

    /// 当前最新请求序号（0 = 还没有请求）
    public private(set) var latest: Int

    public init() {
        latest = 0
    }

    /// 取下一个请求序号（发起请求时调用）
    @discardableResult
    public mutating func next() -> Int {
        latest += 1
        return latest
    }

    /// 该序号是否仍是最新一次请求（0 号是「还没有请求」占位，永远不接受）
    public func accepts(_ sequence: Int) -> Bool {
        sequence > 0 && sequence == latest
    }

    /// 作废全部在途请求（结果返回时一律丢弃）
    public mutating func invalidate() {
        latest += 1
    }
}
