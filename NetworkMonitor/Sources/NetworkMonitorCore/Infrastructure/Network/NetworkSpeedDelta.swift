import Darwin
import Foundation

// MARK: - 网络速度差分（纯逻辑，可被 TestRunner 直接断言）

/// 网卡字节计数差分：把「两次采样之间每个网卡涨了多少」算成总增量。
///
/// 抽成纯函数的原因：这段逻辑有三条真实踩过的边界（网卡消失、计数回退、首帧），
/// 混在 NetworkSpeedMonitor.poll() 里只能靠真机验证；抽出来后每条都能断言。
public enum NetworkSpeedDelta {

    public struct Bytes: Equatable, Sendable {
        public var rx: UInt64
        public var tx: UInt64

        public static let zero = Bytes(rx: 0, tx: 0)

        public init(rx: UInt64, tx: UInt64) {
            self.rx = rx
            self.tx = tx
        }
    }

    /// 计算两次采样之间的总增量
    ///
    /// - 首次出现（previous 里没有该网卡）：不计入增量（没有基线，增量未知）
    /// - 计数回退（current < previous，网卡重置或 32 位回绕）：按当前值兜底，而不是下溢
    /// - 网卡消失：不参与计算（由调用方用 current 重建基线，等价于丢弃）
    public static func compute(previous: [String: (rx: UInt64, tx: UInt64)],
                               current: [String: (rx: UInt64, tx: UInt64)]) -> Bytes {
        var total = Bytes.zero
        for (iface, value) in current {
            guard let prev = previous[iface] else { continue }
            let rxDiff = value.rx >= prev.rx ? value.rx - prev.rx : value.rx
            let txDiff = value.tx >= prev.tx ? value.tx - prev.tx : value.tx
            total.rx &+= rxDiff
            total.tx &+= txDiff
        }
        return total
    }
}
