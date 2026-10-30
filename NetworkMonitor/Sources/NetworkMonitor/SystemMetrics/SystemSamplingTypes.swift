import Foundation
import NetworkMonitorCore

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

/// 单块块存储设备的累计计数（字节 / 操作数 / 服务时间）
///
/// 直接复用 Core 的 DiskIOCounters：差分与配对函数（SystemMetricsCalculations.diskThroughput）
/// 的入参就是这张表的元素类型，采样器若另立同构结构体就要在两侧来回转换，
/// 白白多一处口径漂移风险。名字保留 DiskTransfer 以维持既有调用点语义。
typealias DiskTransfer = DiskIOCounters

/// 磁盘累计传输表：key 为 IORegistryEntryID
///
/// 必须用注册表 entryID 配对，禁止按数组下标配对：多实例（内置盘 + 外置盘）顺序不保证稳定，
/// 实测按下标配对会算出负速率（-339133 MB/s）。
typealias DiskTransferTable = [UInt64: DiskTransfer]
