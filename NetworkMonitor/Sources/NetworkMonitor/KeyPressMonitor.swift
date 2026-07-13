import AppKit
import ApplicationServices
import NetworkMonitorCore

/// 击键计数器：监听键盘按键事件，仅计数不记录内容
/// 使用 NSEvent.addGlobalMonitorForEvents 监听全局键盘事件
final class KeyPressMonitor {

    // MARK: - 属性

    private let database: DatabaseManager
    private var monitor: Any?
    private var isRunning = false

    /// 击键计数器
    private var keyPressCount: Int = 0
    private let flushInterval: TimeInterval = 60
    private var flushTimer: DispatchSourceTimer?

    // MARK: - 初始化

    init(database: DatabaseManager) {
        self.database = database
    }

    deinit {
        stop()
    }

    // MARK: - 启动/停止

    /// 启动击键监听（需要输入监控权限）
    /// 返回 true 表示成功启动，false 表示权限不足
    func start() -> Bool {
        guard !isRunning else { return true }

        // 检查辅助功能/输入监控权限
        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("⌨️ 击键监听启动失败 — 需要辅助功能权限")
            return false
        }

        // 使用 NSEvent 全局监听（比 CGEvent.tapCreate 更稳定）
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            self?.incrementCount()
        }

        guard monitor != nil else {
            print("⌨️ 击键监听启动失败 — 无法创建全局事件监听器")
            return false
        }

        // 启动定时刷新（每60秒写入一次数据库）
        startFlushTimer()

        isRunning = true
        print("⌨️ 击键监听已启动 ✅")
        return true
    }

    /// 停止击键监听
    func stop() {
        guard isRunning else { return }

        flushTimer?.cancel()
        flushTimer = nil

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        // 写入剩余计数
        flushCount()

        isRunning = false
        print("⌨️ 击键监听已停止")
    }

    // MARK: - 计数与写入

    /// 递增击键计数（可在任意线程调用）
    private func incrementCount() {
        keyPressCount += 1
    }

    /// 启动定时刷新
    private func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushCount()
        }
        timer.resume()
        flushTimer = timer
    }

    /// 将累计的击键数写入数据库并重置计数器
    private func flushCount() {
        let count = keyPressCount
        guard count > 0 else { return }

        keyPressCount = 0

        // 写入一条带计数的事件到数据库
        let timestamp = Date().timeIntervalSince1970
        database.writeKeyPressBatch(count: count, timestamp: timestamp)

        print("⌨️ 写入 \(count) 次击键")
    }
}
