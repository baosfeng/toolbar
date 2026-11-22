import Foundation
import NetworkMonitorCore

// MARK: - 触发原因

/// 一轮自动索引是被什么触发的（日志 / 探针用，也便于将来按来源做节流）
enum TokenAutoIndexTrigger: String, Sendable {
    /// 定时器到点（主路径）
    case timer
    /// 系统唤醒 / 解锁后补跑
    case wake
    /// 手动（面板刷新 / 设置页动作）
    case manual

    /// 日志里的中文名
    var displayName: String {
        switch self {
        case .timer: return "定时"
        case .wake: return "唤醒补跑"
        case .manual: return "手动"
        }
    }
}

// MARK: - 调度口径

// 时间口径（首次延迟 / 间隔归一 / 下一轮时间）已下沉到 Core：
// NetworkMonitorCore/Harness/TokenAutoIndexSchedule.swift（TestRunner 能直接断言）。
// 本文件只保留定时器、屏幕活动订阅与探针。

// MARK: - 调度器

/// Token 后台自动增量索引调度器
///
/// 职责边界：
/// - 只管「什么时候扫」，扫描本身仍在 `HarnessUsageServicing` 的后台串行队列（既有能力）；
/// - 同一时刻只允许一轮：本轮未结束时的触发只记一个「待跑」，结束后合并成一轮；
/// - 一轮结束后再算下一次，不追帧；锁屏 / 休眠暂停，唤醒补跑一次；
/// - 只跑已启用且已实现的来源（由多来源扫描器按偏好决定，这里只负责记日志）。
///
/// 线程模型：全部状态与定时器都在私有串行队列 `queue` 上，`setActive` / `trigger` / `start`
/// 从任意线程进来只做一次 async 投递；定时器是 `DispatchSourceTimer` 且挂在这条队列上，
/// 不占主线程（索引重活在服务的队列里）。
///
/// `NM_TOKEN_AUTOINDEX_PROBE=1` 时输出启停与每轮触发的来源 / 耗时（走 logger，不用 print）。
final class TokenAutoIndexScheduler: @unchecked Sendable {

    /// 探针环境变量（与 NM_SNAPSHOT_FREEZE / NM_DRAWN_PROBE 同一惯例）
    static let probeEnvironmentKey = "NM_TOKEN_AUTOINDEX_PROBE"

    private let service: any HarnessUsageServicing
    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let queue = DispatchQueue(label: "com.bsfeng.yilan.tokenAutoIndex", qos: .utility)
    private let probeEnabled: Bool

    /// 队列内状态
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var isPaused = false
    private var isStopped = false
    private var pendingTrigger: TokenAutoIndexTrigger?

    /// 屏幕活动监听的原回调（链式订阅，停止时还原）
    @MainActor private var previousOnChange: ((Bool) -> Void)?

    init(service: any HarnessUsageServicing,
         storage: any KeyValueStorage,
         logger: LoggingService,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.service = service
        self.storage = storage
        self.logger = logger
        self.probeEnabled = environment[Self.probeEnvironmentKey] == "1"
    }

    // MARK: - 生命周期

    /// 启动：自动监控开着就排第一轮，关着则完全不排（零触发）
    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            let enabled = TokenSourcePreferences.autoIndexEnabled(self.storage)
            let interval = TokenSourcePreferences.autoIndexInterval(self.storage)
            self.probe("启动：自动监控" + (enabled ? "已开启" : "关闭（不排定时器）")
                       + "，间隔 " + Self.format(interval) + "s")
            guard enabled, !self.isPaused else { return }
            self.scheduleTimer(after: TokenAutoIndexSchedule.firstFireDelay)
        }
    }

    /// 停止：取消定时器、丢弃排队请求（幂等，可重复调用）
    func stop() {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.isStopped = true
            self.pendingTrigger = nil
            self.timer?.cancel()
            self.timer = nil
            self.probe("停止：定时器已取消")
        }
    }

    // MARK: - 触发入口

    /// 手动触发一轮（面板刷新 / 设置页动作）：不受自动监控开关限制
    func triggerNow() { trigger(.manual) }

    /// 按原因触发一轮
    func trigger(_ reason: TokenAutoIndexTrigger) {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            self.enqueue(reason)
        }
    }

    /// 屏幕活动变化（主线程回调进来）：不可用 → 暂停；恢复 → 补跑一轮
    func setActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self, !self.isStopped else { return }
            if active {
                guard self.isPaused else { return }
                self.isPaused = false
                self.probe("恢复可用：补跑一轮")
                self.enqueue(.wake)
            } else {
                guard !self.isPaused else { return }
                self.isPaused = true
                self.timer?.cancel()
                self.timer = nil
                self.probe("锁屏 / 休眠：暂停定时器")
            }
        }
    }

    // MARK: - 屏幕活动订阅（链式，不覆盖额度侧的既有订阅）

    /// 订阅 `ScreenActivityMonitor`
    ///
    /// `onChange` 是单槽回调，额度链路（先装配）已经占了它。这里**链式包一层**：
    /// 先调原回调再调本调度器，停止时还原原回调 —— 不新增第二套监听，也不与额度抢槽。
    @MainActor
    func bind(to monitor: ScreenActivityMonitor) {
        let previous = monitor.onChange
        previousOnChange = previous
        monitor.onChange = { [weak self] active in
            previous?(active)
            self?.setActive(active)
        }
        setActive(monitor.isActive)
    }

    /// 还原 `ScreenActivityMonitor.onChange`
    @MainActor
    func unbind(_ monitor: ScreenActivityMonitor) {
        guard let previous = previousOnChange else { return }
        monitor.onChange = previous
        previousOnChange = nil
    }

    // MARK: - 队列内实现

    /// 入队一次触发：跑着的合并成「待跑」，空闲的立即开跑
    private func enqueue(_ reason: TokenAutoIndexTrigger) {
        guard !isPaused else { return }
        guard !isRunning else {
            // 合并：一轮之内来多少次触发都只补跑一轮
            pendingTrigger = pendingTrigger ?? reason
            return
        }
        run(reason)
    }

    /// 跑一轮（服务侧串行队列负责真正的单飞，这里只跟踪状态与耗时）
    private func run(_ reason: TokenAutoIndexTrigger) {
        isRunning = true
        let sources = enabledSourcesText()
        let startedAt = Date()
        probe("触发（" + reason.displayName + "）：来源 " + sources)
        service.refreshIfNeeded { [weak self] in
            guard let self else { return }
            self.queue.async {
                let elapsed = Date().timeIntervalSince(startedAt)
                self.isRunning = false
                self.probe("完成（" + reason.displayName + "）：来源 " + sources
                           + "，耗时 " + Self.format(elapsed) + "s；" + self.sourceTotalsText())
                self.scheduleNextRoundIfEnabled()
                // 本轮期间攒下的触发：合并成一轮立刻补跑（不丢请求）
                if let pending = self.pendingTrigger, !self.isStopped, !self.isPaused {
                    self.pendingTrigger = nil
                    self.run(pending)
                }
            }
        }
    }

    /// 一轮结束后按「结束时间 + 间隔」排下一轮（关着就不排）
    private func scheduleNextRoundIfEnabled() {
        guard !isStopped, !isPaused else { return }
        guard TokenSourcePreferences.autoIndexEnabled(storage) else {
            timer?.cancel()
            timer = nil
            return
        }
        let interval = TokenSourcePreferences.autoIndexInterval(storage)
        let fireDate = TokenAutoIndexSchedule.nextFireDate(after: Date(), interval: interval)
        scheduleTimer(after: fireDate.timeIntervalSinceNow)
    }

    /// 排一个单次定时器（一次性 + 结束时重排 = 天然不追帧）
    private func scheduleTimer(after delay: TimeInterval) {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, delay))
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped, !self.isPaused else { return }
            self.enqueue(.timer)
        }
        timer.resume()
        self.timer = timer
    }

    // MARK: - 日志

    /// 已启用且已实现的来源（多来源扫描器按同一偏好过滤，这里只用于日志）
    private func enabledSourcesText() -> String {
        let sources = TokenSourcePreferences.enabledSources(storage).filter(\.hasIndexer)
        guard !sources.isEmpty else { return "无（全部关闭）" }
        return sources.map(\.displayName).joined(separator: " + ")
    }

    /// 各来源的落库数字（探针用：一轮跑完直接把 bySource 打出来，省得再查库对账）
    private func sourceTotalsText() -> String {
        let bySource = service.snapshot().bySource
        guard !bySource.isEmpty else { return "各来源无数据" }
        let parts = bySource.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { source -> String? in
            guard let item = bySource[source] else { return nil }
            return source.rawValue + " " + String(item.usage.totalTokens) + " tok / "
                + String(item.sessionCount) + " 会话"
        }
        let total = service.snapshot().totals.allTime.totalTokens
        let sum = bySource.values.reduce(0) { $0 + $1.usage.totalTokens }
        return "各来源：" + parts.joined(separator: "，")
            + "；全量 " + String(total) + " = 单源之和 " + String(sum)
    }

    /// 探针日志（只在 NM_TOKEN_AUTOINDEX_PROBE=1 时输出）
    private func probe(_ message: String) {
        guard probeEnabled else { return }
        logger.info("[TOKEN-AUTOINDEX] " + message)
    }

    /// 秒数格式化（两位小数，日志口径统一）
    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", seconds)
    }
}
