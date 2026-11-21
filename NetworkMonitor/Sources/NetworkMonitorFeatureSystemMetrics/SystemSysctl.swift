import Darwin
import Foundation

// MARK: - sysctl 读取辅助

/// 读取 32 位整数 sysctl
///
/// 键不存在（旧系统 / Intel）或类型不符时返回 nil，由调用方降级处理，不抛错。
func sysctlInt32(_ name: String) -> Int32? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}

/// 读取 64 位整数 sysctl（hw.memsize 等）
func sysctlUInt64(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}
