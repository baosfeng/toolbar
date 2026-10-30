import Foundation
import IOKit
import NetworkMonitorCore

// MARK: - GPU 功耗采样（IOReport Energy Model，私有 API）

/// 通过 IOReport 读 GPU 能耗累加器
///
/// 为什么单文件：IOReport 是私有符号，只允许出现在 NetworkMonitor（可执行目标）；
/// 且它的引用持有方式极易 SIGSEGV，必须集中在一个文件里按唯一稳定写法实现。
///
/// 单位：Energy Model 组的 GPU Energy 单位是 **nJ**（实测 raw 290295980 → 0.29 W）。
/// 同组混着 uJ / nJ / mJ，因此单位一律读通道自带 label，禁止硬编码。
/// 只有 GPU Energy 有值：CPU Energy / DRAM0 / ANE0 等在本机恒 0，无法合成整机功耗。
///
/// 实测成本：全组 162 通道一次读取 1.76 ms → 5 秒一次（均摊 0.35 ms/s）。
///
/// 线程模型：subscription / 基线只允许在采样串行队列访问，故标 @unchecked Sendable。
final class SystemGPUPowerReader: @unchecked Sendable {

    // MARK: 私有符号签名

    private typealias CopyChannelsInGroupFunction = @convention(c) (CFString, CFString?, UInt64, UInt64,
                                                                   UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscriptionFunction = @convention(c) (UnsafeRawPointer?, CFDictionary,
                                                                  UnsafeMutablePointer<Unmanaged<CFDictionary>?>?,
                                                                  UInt64, UnsafeRawPointer?) -> OpaquePointer?
    private typealias CreateSamplesFunction = @convention(c) (OpaquePointer, CFDictionary?,
                                                              UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDeltaFunction = @convention(c) (CFDictionary, CFDictionary,
                                                                  UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    private typealias ChannelGetNameFunction = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias ChannelGetUnitFunction = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias SimpleGetIntegerFunction = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias StateGetCountFunction = @convention(c) (CFDictionary) -> Int32

    /// 初始化成功后缓存的可复用会话
    private struct Session {
        let subscription: OpaquePointer
        /// 订阅返回的通道字典必须持有强引用（只留局部变量会偶发崩）
        let subscribedChannels: CFDictionary
        let copySamples: CreateSamplesFunction
        let copySamplesDelta: CreateSamplesDeltaFunction
        let channelName: ChannelGetNameFunction
        let channelUnit: ChannelGetUnitFunction
        let simpleGetInteger: SimpleGetIntegerFunction
        let stateGetCount: StateGetCountFunction
    }

    private enum State {
        case unavailable
        case ready(Session)
    }

    /// Energy Model 组名（实测本机 162 个通道）
    private static let groupName = "Energy Model"
    /// 关注的通道名（只有它在本机有值）
    private static let channelName = "GPU Energy"

    private var state: State?
    /// 上一帧的累计能量样本（首帧只建基线）
    private var previousSample: CFDictionary?
    /// 上一帧样本时刻（用于除以真实间隔）
    private var previousSampleDate: Date?

    // MARK: - 读取

    /// 读取一次 GPU 功耗
    ///
    /// - Parameter elapsed: 与上一次成功读取的时间间隔（秒）；≤ 0 或首帧 → nil
    /// - Returns: 瓦数；IOReport 不可用 / 通道缺失 / 首帧 / 计数倒退 → nil
    func read(elapsed: TimeInterval) -> Double? {
        guard let session = ensureSession() else { return nil }
        guard let sample = currentSample(session) else { return nil }

        defer {
            previousSample = sample
            previousSampleDate = Date()
        }
        guard let previous = previousSample, elapsed > 0 else { return nil }

        guard let delta = copyDelta(session, previous: previous, current: sample),
              let nanojoules = gpuEnergyNanojoules(delta, session: session) else { return nil }
        return SystemMetricsSupplementCalculations.wattsFromEnergyDelta(nanojoules: nanojoules,
                                                                        elapsedSeconds: elapsed)
    }

    /// 丢弃基线（例如采样周期变化后避免用旧间隔算功率）
    func resetBaseline() {
        previousSample = nil
        previousSampleDate = nil
    }

    // MARK: - 采样

    private func currentSample(_ session: Session) -> CFDictionary? {
        session.copySamples(session.subscription, session.subscribedChannels, nil)?.takeRetainedValue()
    }

    private func copyDelta(_ session: Session,
                           previous: CFDictionary,
                           current: CFDictionary) -> CFDictionary? {
        session.copySamplesDelta(previous, current, nil)?.takeRetainedValue()
    }

    /// 从差分样本取出 GPU Energy 的纳焦耳值
    ///
    /// - 通道元素必须用 NSDictionary 强引用保住（裸 CFDictionary 会被过度释放 → 段错误）；
    /// - simple / state 通道用 IOReportStateGetCount 判断，**不用 IOReportChannelGetFormat**；
    /// - 单位读通道自带 label 并按 uJ / nJ / mJ 换算成纳焦耳。
    private func gpuEnergyNanojoules(_ delta: CFDictionary, session: Session) -> UInt64? {
        for item in Self.channelItems(delta) {
            let channel = item as CFDictionary
            guard let rawName = session.channelName(channel) else { continue }
            guard rawName.takeUnretainedValue() as String == Self.channelName else { continue }
            // simple 通道返回 -1，state 通道返回 >= 2
            guard session.stateGetCount(channel) < 0 else { continue }
            let raw = session.simpleGetInteger(channel, 0)
            guard raw >= 0 else { return nil }
            let unit = session.channelUnit(channel).map { $0.takeUnretainedValue() as String } ?? ""
            return Self.nanojoules(raw: UInt64(raw), unit: unit)
        }
        return nil
    }

    /// 按单位标签把裸值换算成纳焦耳
    ///
    /// 未知单位一律返回 nil（宁可降级显示「—」，也不猜测量纲出「0.29 kW」这种荒谬读数）。
    private static func nanojoules(raw: UInt64, unit: String) -> UInt64? {
        switch unit {
        case "nJ": return raw
        case "uJ": return raw &* 1_000
        case "mJ": return raw &* 1_000_000
        case "J": return raw &* 1_000_000_000
        default: return nil
        }
    }

    /// 把 IOReportChannels 数组转成强引用的 NSDictionary 列表
    private static func channelItems(_ dict: CFDictionary) -> [NSDictionary] {
        guard let array = (dict as NSDictionary)["IOReportChannels"] as? NSArray else { return [] }
        var items: [NSDictionary] = []
        items.reserveCapacity(array.count)
        for index in 0..<array.count {
            items.append(array.object(at: index) as! NSDictionary)
        }
        return items
    }

    // MARK: - 初始化

    private func ensureSession() -> Session? {
        if let state {
            switch state {
            case .unavailable: return nil
            case .ready(let session): return session
            }
        }
        let created = Self.makeSession()
        state = created.map { State.ready($0) } ?? .unavailable
        if case .ready(let session) = state { return session }
        return nil
    }

    private static func makeSession() -> Session? {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        guard let copyChannelsInGroup = symbol(handle, "IOReportCopyChannelsInGroup",
                                               as: CopyChannelsInGroupFunction.self),
              let createSubscription = symbol(handle, "IOReportCreateSubscription",
                                              as: CreateSubscriptionFunction.self),
              let copySamples = symbol(handle, "IOReportCreateSamples",
                                       as: CreateSamplesFunction.self),
              let copySamplesDelta = symbol(handle, "IOReportCreateSamplesDelta",
                                            as: CreateSamplesDeltaFunction.self),
              let channelName = symbol(handle, "IOReportChannelGetChannelName",
                                       as: ChannelGetNameFunction.self),
              let channelUnit = symbol(handle, "IOReportChannelGetUnitLabel",
                                       as: ChannelGetUnitFunction.self),
              let simpleGetInteger = symbol(handle, "IOReportSimpleGetIntegerValue",
                                            as: SimpleGetIntegerFunction.self),
              let stateGetCount = symbol(handle, "IOReportStateGetCount",
                                         as: StateGetCountFunction.self) else {
            return nil
        }

        // 必须按 group 名订阅：先 CopyAllChannels（9225 个）再订阅必然失败
        guard let rawChannels = copyChannelsInGroup(groupName as CFString, nil, 0, 0, nil) else {
            return nil
        }
        let channels = rawChannels.takeRetainedValue()
        var subscribedRaw: Unmanaged<CFDictionary>?
        guard let subscription = createSubscription(nil, channels, &subscribedRaw, 0, nil),
              let subscribed = subscribedRaw?.takeRetainedValue() else {
            return nil
        }
        return Session(subscription: subscription,
                       subscribedChannels: subscribed,
                       copySamples: copySamples,
                       copySamplesDelta: copySamplesDelta,
                       channelName: channelName,
                       channelUnit: channelUnit,
                       simpleGetInteger: simpleGetInteger,
                       stateGetCount: stateGetCount)
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
        guard let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}
