import AppKit
import Foundation
import NetworkMonitorCore

// MARK: - 主线程看门狗

/// 主线程看门狗 — 后台 0.5 s 一跳，心跳间隔超过阈值记一条 os_log
///
/// 心跳有三个来源（都由主线程写）：
/// - **看护线程自己投到主线程的心跳块**：主线程活着就会很快执行，卡住时它一直排队。
///   这是不依赖业务定时器的活性判据 —— 面板在省电档是 2 s 一跳，只靠 tick 打点会把
///   正常节拍误判成停顿（实现时踩过：省电档下每 2 s 记一条假停顿）。
/// - `MenuPanelController.tick()`：顺带带回「当前分页 / 展开态 / 索引状态」上下文
/// - sendEvent 路径（本地事件监听）：面板收起时也能量到主线程是否还在跑
///
/// 看护线程**不回头问主线程**：它只读「最后一次心跳时存下的上下文」。主线程真卡住时，
/// 若看护线程去问主线程「你在哪一页」，它自己也会被卡住，什么也记不下来。
public final class MainThreadWatchdog: @unchecked Sendable {

    private let logger: any LoggingService
    private let lock = NSLock()
    /// 心跳现场（锁内读改写，判定口径在 MainThreadHeartbeat）
    private var heartbeatState: MainThreadHeartbeat
    private var timer: DispatchSourceTimer?
    private var eventMonitor: Any?

    public init(logger: any LoggingService = AppContext.shared.logger) {
        self.logger = logger
        self.heartbeatState = MainThreadHeartbeat(now: DispatchTime.now().uptimeNanoseconds)
    }

    deinit {
        timer?.cancel()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    // MARK: - 生命周期

    /// 启动看护（主线程调用：本地事件监听必须装在主线程）
    public func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.bsfeng.yilan.mainThreadWatchdog", qos: .utility)
        )
        source.schedule(deadline: .now() + MainThreadWatchdogPolicy.tickSeconds,
                        repeating: MainThreadWatchdogPolicy.tickSeconds)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
            self?.heartbeat()
            return event
        }
#if DEBUG
        scheduleStallEvidenceIfRequested()
#endif
    }

    // MARK: - 看护节拍

    /// 一跳两件事：先向主线程投心跳块（主线程卡住时它会排队），再判定上次心跳距今多久
    private func tick() {
        DispatchQueue.main.async { [weak self] in self?.heartbeat() }
        checkForStall()
    }

    // MARK: - 心跳

    /// 只打点（心跳块 / sendEvent 等高频路径）
    public func heartbeat() {
        lock.lock()
        heartbeatState.beat(at: DispatchTime.now().uptimeNanoseconds)
        lock.unlock()
    }

    /// 打点 + 更新「停顿现场」上下文（tick 路径，每个刷新节拍一次）
    public func beat(tab: String, panelShown: Bool, indexingState: String) {
        lock.lock()
        heartbeatState.beat(at: DispatchTime.now().uptimeNanoseconds, tab: tab,
                            panelShown: panelShown, indexingState: indexingState)
        lock.unlock()
    }

    // MARK: - 判定

    private func checkForStall() {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let stall = heartbeatState.takeStall(at: now)
        lock.unlock()
        // 只记一条：间隔继续增长也不刷屏，等心跳恢复（主线程能跑心跳块）才清位
        guard let stall else { return }
        logger.warning(MainThreadWatchdogPolicy.message(gapSeconds: stall.gapSeconds, tab: stall.tab,
                                                        panelShown: stall.panelShown,
                                                        indexingState: stall.indexingState))
    }
}

#if DEBUG

// MARK: - 取证入口（仅 DEBUG）

extension MainThreadWatchdog {

    /// 取证开关：`NM_WATCHDOG_STALL_MS=3000` 时启动 3 s 后人为阻塞主线程一次
    ///
    /// 用途：证明「主线程停顿 → 看门狗日志真的落下来」（`log show --predicate 'process == "一览"'`）。
    /// 生产构建不包含本分支。
    public static let stallEvidenceEnvKey = "NM_WATCHDOG_STALL_MS"

    public func scheduleStallEvidenceIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment[Self.stallEvidenceEnvKey],
              let milliseconds = Int(raw), milliseconds > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            AppContext.shared.logger.info("看门狗取证：主线程将阻塞 \(milliseconds) ms")
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1000)
            AppContext.shared.logger.info("看门狗取证：主线程阻塞结束")
        }
    }
}

#endif
