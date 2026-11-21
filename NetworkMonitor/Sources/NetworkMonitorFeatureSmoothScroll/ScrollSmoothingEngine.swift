import CoreGraphics
import NetworkMonitorCore
import QuartzCore

// MARK: - 滚轮平滑引擎

/// 鼠标滚轮平滑引擎 —— 全局事件 tap + 显示帧循环 + 回投队列
///
/// 数据流：
/// 1. `.cgSessionEventTap`（`.headInsertEventTap` / `.defaultTap`）拿到 `.scrollWheel`；
/// 2. 只接管「纯鼠标滚轮」：触控板 / 惯性 / 连续滚动原样放行（判据见 `ScrollEventClassifier`）；
/// 3. 按参数把它拆成逐帧位移，**吞掉原始事件**并返回 nil；
/// 4. 显示帧回调（`NSScreen.displayLink`）每帧回投一条带魔数标记的像素级滚轮事件。
///
/// fail-open 是硬约束（这是常驻的全局输入路径）：
/// - 建 tap 失败 / 被环境变量关掉 / tap 连续被系统禁用 → 立刻停止接管，滚动回到系统原生行为；
/// - 回调里任何一条判据不成立都 `passUnretained` 原样放行，绝不吞掉「不确定」的事件；
/// - 回调线程不是主线程时同样直接放行（不在非主线程碰 @MainActor 状态）。
///
/// 线程模型：tap 挂在主 run loop 上，回调必在主线程；引擎整体 @MainActor，
/// 显示帧回调也在主线程，因此注入队列与残余量不需要加锁。
@MainActor
public final class ScrollSmoothingEngine {

    // MARK: - 一帧要回投的位移

    /// 单帧位移 + 从原始事件继承的修饰键
    /// internal：回投队列在扩展文件（+Injection）里读写，同 target 内可见
    struct ScrollFrame {
        var vertical: Double
        var horizontal: Double
        var flags: CGEventFlags
    }

    // MARK: - 依赖（internal：扩展文件 +Tap / +Injection 要读写，同 target 内可见）

    /// 偏好读写（每次 `reload()` 重新读，写偏好即热生效）
    let settings: SmoothScrollSettings
    let logger: any LoggingService
    /// 进程环境（kill switch 判定；测试注入）
    let environment: [String: String]
    /// 刷新率来源（默认读主屏 `maximumFramesPerSecond`；测试注入固定值）
    let refreshRateProvider: (@MainActor () -> Double)?

    // MARK: - 运行状态

    /// 对外状态（设置页显示一行说明；setter 放宽到 internal：+Tap 扩展要写入）
    public internal(set) var state: ScrollSmoothingEngineState = .idle

    /// 是否正在接管
    public var isRunning: Bool { state == .running }

    /// 当前生效参数（已归一化）
    var parameters: SmoothScrollParameters
    /// 事件 tap 与它的 run loop source（+Tap 扩展安装 / 拆除）
    ///
    /// 放在**非隔离**的句柄盒子里：`deinit` 是 nonisolated，碰不到 @MainActor 属性，
    /// 而「tap 还在、引擎没了」= 悬空指针 + 无人启用的全局事件拦截。
    let handles = ScrollSmoothingTapHandles()
    /// 显示帧驱动（只在有待回投帧时存在）
    var displayLink: CADisplayLink?
    /// 待回投帧队列（FIFO）
    var pendingFrames: [ScrollFrame] = []
    /// 像素取整后的余量（保证总量不丢：一帧不足 1 像素时累积到下一帧）
    var verticalResidual: Double = 0
    var horizontalResidual: Double = 0
    /// tap 连续禁用计数（+Tap 扩展读健康度）
    var health = ScrollTapHealth()
    /// 是否已因连续禁用来停用（等用户关掉再打开才重试）
    var didGiveUp = false

    // MARK: - 常量

    /// 回投队列上限：一次手势积压超过这么多帧就丢最旧的（有界，防失控）
    static let maximumPendingFrames = 480
    /// 单帧残余量的绝对值上限（防异常增量把 Int32 转换打爆）
    static let maximumResidualMagnitude = 1_000_000.0

    // MARK: - 初始化

    /// - Parameters:
    ///   - settings: 偏好读写口（组合根注入同一份 storage）
    ///   - logger: 日志（必传，功能层不取 AppContext.shared）
    ///   - environment: 进程环境（kill switch）
    ///   - refreshRateProvider: 刷新率来源（nil = 读主屏）
    public init(settings: SmoothScrollSettings,
                logger: any LoggingService,
                environment: [String: String] = ProcessInfo.processInfo.environment,
                refreshRateProvider: (@MainActor () -> Double)? = nil) {
        self.settings = settings
        self.logger = logger
        self.environment = environment
        self.refreshRateProvider = refreshRateProvider
        self.parameters = settings.parameters
    }

    // MARK: - 生命周期

    /// 按偏好启动（幂等；已运行或不该运行时什么都不做）
    public func start() {
        guard state != .running else { return }
        parameters = settings.parameters
        guard parameters.enabled else {
            state = .idle
            return
        }
        guard !ScrollSmoothingKillSwitch.isDisabled(environment: environment) else {
            state = .disabledByEnvironment
            logger.warning("鼠标滚轮平滑被环境变量 \(ScrollSmoothingKillSwitch.environmentKey) 关闭，不接管滚动")
            return
        }
        guard installTap() else {
            state = .tapUnavailable
            logger.warning("鼠标滚轮平滑无法创建事件 tap（通常是缺少「辅助功能」权限），滚动保持系统原生行为")
            return
        }
        health = ScrollTapHealth()
        didGiveUp = false
        state = .running
        logger.info("鼠标滚轮平滑已启用（仅纯鼠标滚轮；触控板与惯性滚动原样放行）")
    }

    /// 停止接管（幂等）：拆 tap、停帧循环、丢队列
    public func stop() {
        let wasRunning = state == .running
        removeTap()
        stopDisplayLink()
        pendingFrames.removeAll()
        verticalResidual = 0
        horizontalResidual = 0
        health = ScrollTapHealth()
        didGiveUp = false
        state = .idle
        if wasRunning {
            logger.info("鼠标滚轮平滑已停止，滚动恢复系统原生行为")
        }
    }

    /// 兜底：引擎被释放时 tap 绝不允许残留在系统里
    ///
    /// tap 用 `passUnretained(self)` 拿回引擎（不持有，避免 self 被引擎自己的回调永久留住），
    /// 所以「tap 还活着而引擎没了」就是悬空指针 + 无人启用的全局事件拦截。
    /// 正常路径由 `stop()` 收尾；这里只是最后一道保险（deinit 里只碰 CF 层，不碰 UI）。
    deinit {
        if let tap = handles.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = handles.source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    /// 重新读偏好并热生效（设置页每次写偏好后调用）
    ///
    /// - 关掉 → 立即停止接管；
    /// - 打开 → 未运行时启动；已在运行则只更新参数（不重建 tap）；
    /// - 已因连续禁用来停用的，保持停用直到用户把它关掉再打开。
    public func reload() {
        parameters = settings.parameters
        guard parameters.enabled else {
            if state != .idle { stop() }
            return
        }
        if state == .running { return }
        if didGiveUp { return }
        start()
    }

}