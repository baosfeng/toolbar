import Darwin
import Foundation
import NetworkMonitorCore

// MARK: - 进程采样

// MARK: libproc 绑定
//
// 只能手写 @_silgen_name：仅 CommandLineTools 环境没有 libproc 模块可 import。
// proc_taskinfo 在 Swift 里不会自动布局，必须按 C 头顺序自己写（96 字节 / 18 字段）。

/// proc_taskinfo（与 sys/proc_info.h 字段顺序、宽度严格一致）
///
/// 布局错一个字段会让 proc_pidinfo 返回 -1，表现为「所有进程都读不到」而不是崩溃，
/// 因此本结构体必须保持 96 字节；改动后用 MemoryLayout<ProcTaskInfo>.size 断言。
struct ProcTaskInfo {
    var pti_virtual_size: UInt64
    var pti_resident_size: UInt64
    var pti_total_user: UInt64
    var pti_total_system: UInt64
    var pti_threads_user: UInt64
    var pti_threads_system: UInt64
    var pti_policy: Int32
    var pti_faults: Int32
    var pti_pageins: Int32
    var pti_cow_faults: Int32
    var pti_messages_sent: Int32
    var pti_messages_received: Int32
    var pti_syscalls_mach: Int32
    var pti_syscalls_unix: Int32
    var pti_csw: Int32
    var pti_threadnum: Int32
    var pti_numrunning: Int32
    var pti_priority: Int32
}

@_silgen_name("proc_listpids")
private func proc_listpids(_ type: UInt32, _ typeinfo: UInt32,
                           _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64,
                          _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
private func proc_name(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

/// PROC_PIDTASKINFO = 4（sys/proc_info.h，头文件不可 import 故本地定义）
private let procPIDTaskInfoFlavor: Int32 = 4
/// PROC_ALL_PIDS = 1
private let procAllPIDsType: UInt32 = 1

/// 进程资源采样 — proc_listpids 枚举 + proc_pidinfo(PROC_PIDTASKINFO) 差分
///
/// 实测成本：proc_listpids 0.096 ms，单进程 proc_pidinfo 0.007 ms，
/// 全量扫 500+ 进程约 1.0 ms → 5 秒一次足够（均摊 0.2 ms/s）。
///
/// 大量进程 proc_pidinfo 返回 -1（权限 / 僵尸 / 已退出）是正常现象，
/// 本机实测 528 个 pid 里约 326 个可读，**不得当错误刷日志**。
enum SystemProcessSampler {

    /// 进程榜缓存条数 — 「压力详情」要 Top-10，首屏只显示前 2 条
    static let topLimit = 10

    /// 一次全量扫描结果
    struct ScanResult: Sendable {
        /// pid → 累计 CPU ticks 与常驻内存
        let baselines: [Int32: ProcessCPUTimeBaseline]
        /// pid → 进程名（仅对成功读到 taskinfo 的进程取名字，省一次系统调用）
        let names: [Int32: String]
    }

    /// mach_timebase_info 的 ns/tick（运行时读取一次）
    ///
    /// 禁止硬编码 41.6667：Apple Silicon 是 125/3，Intel 是 1/1，
    /// 硬编码在 Intel 上会反向放大 41.67 倍。timebase 运行期不变，缓存即可。
    static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0, info.numer != 0 else { return 1 }
        return Double(info.numer) / Double(info.denom)
    }()

    /// 全量扫描一次进程
    ///
    /// - Returns: nil 表示 proc_listpids 失败（整项不可用）；否则给出本次读数。
    static func scan() -> ScanResult? {
        guard let pids = allPIDs() else { return nil }
        var baselines = [Int32: ProcessCPUTimeBaseline]()
        var names = [Int32: String]()
        baselines.reserveCapacity(pids.count)
        for pid in pids {
            guard let info = taskInfo(pid) else { continue }
            baselines[pid] = ProcessCPUTimeBaseline(cpuTicks: info.pti_total_user &+ info.pti_total_system,
                                                    residentBytes: info.pti_resident_size)
            // 名字只对读到的进程取：proc_name 本身也是一次系统调用
            names[pid] = processName(pid)
        }
        return ScanResult(baselines: baselines, names: names)
    }

    // MARK: 私有

    /// 枚举全部 pid（跳过 pid ≤ 0）
    private static func allPIDs() -> [Int32]? {
        let byteCount = proc_listpids(procAllPIDsType, 0, nil, 0)
        guard byteCount > 0 else { return nil }
        // 两次调用之间进程数会变（实测 636 / 708 / 673），多留 64 个槽位缓冲
        let capacity = Int(byteCount) / MemoryLayout<Int32>.size + 64
        var pids = [Int32](repeating: 0, count: capacity)
        let got = proc_listpids(procAllPIDsType, 0, &pids, Int32(capacity * MemoryLayout<Int32>.size))
        guard got > 0 else { return nil }
        return pids.prefix(Int(got) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    /// 读单进程 taskinfo；返回长度不等于结构体大小即视为不可读
    private static func taskInfo(_ pid: Int32) -> ProcTaskInfo? {
        var info = ProcTaskInfo(pti_virtual_size: 0, pti_resident_size: 0,
                                pti_total_user: 0, pti_total_system: 0,
                                pti_threads_user: 0, pti_threads_system: 0,
                                pti_policy: 0, pti_faults: 0, pti_pageins: 0,
                                pti_cow_faults: 0, pti_messages_sent: 0,
                                pti_messages_received: 0, pti_syscalls_mach: 0,
                                pti_syscalls_unix: 0, pti_csw: 0, pti_threadnum: 0,
                                pti_numrunning: 0, pti_priority: 0)
        let expected = Int32(MemoryLayout<ProcTaskInfo>.size)
        let read = proc_pidinfo(pid, procPIDTaskInfoFlavor, 0, &info, expected)
        return read == expected ? info : nil
    }

    /// 进程名（proc_name 截断到 255 字节；失败返回空串，由 UI 显示 pid）
    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        // 按实际写入长度（不含 NUL）截断再解码，替换已废弃的 init(cString:)
        return buffer.withUnsafeBytes { raw in
            String(decoding: raw.prefix(Int(length)), as: UTF8.self)
        }
    }
}
