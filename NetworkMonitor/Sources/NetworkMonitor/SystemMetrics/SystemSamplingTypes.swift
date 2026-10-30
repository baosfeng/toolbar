import Foundation

// MARK: - 采样中间值类型
//
// 跨队列只传值类型（Sendable）：后台采样完成后由主线程回写，禁止共享可变对象。

/// CPU 每核累计 tick 基线
///
/// 每核固定 4 个槽位（user / system / idle / nice），长度 = 核数 × 4。
struct CPUTickBaseline: Sendable {
    let ticks: [UInt32]
}

// MARK: - 磁盘

/// 单块块存储设备的累计读写字节
struct DiskTransfer: Sendable, Equatable {
    let readBytes: UInt64
    let writeBytes: UInt64
}

/// 磁盘累计传输表：key 为 IORegistryEntryID
///
/// 必须用注册表 entryID 配对，禁止按数组下标配对：多实例（内置盘 + 外置盘）顺序不保证稳定，
/// 实测按下标配对会算出负速率（-339133 MB/s）。
typealias DiskTransferTable = [UInt64: DiskTransfer]
