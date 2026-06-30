@preconcurrency import CoreGraphics
import Foundation

/// 击键计数器：监听键盘按键事件，仅计数不记录内容
/// 使用 CGEventTap 监听 kCGEventKeyDown，每60秒向数据库写入一次击键数
final class KeyPressMonitor {

    // MARK: - 属性

    private let database: DatabaseManager
    private var tap: CFMachPort?
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
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

        // 创建事件 Tap
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (_, _, event, refcon) -> Unmanaged<CGEvent>? in
                // 直接传递事件，不做修改
                if let refcon {
                    let monitor = Unmanaged<KeyPressMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.incrementCount()
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⌨️ 击键监听启动失败 — 需要输入监控权限")
            return false
        }

        self.tap = tap

        // 将 Tap 添加到当前线程的 RunLoop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // 在后台线程运行事件循环
        if let source {
            Thread.detachNewThread {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CFRunLoopRun()
            }
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

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }

        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }

        // 停止后台 RunLoop
        CFRunLoopStop(CFRunLoopGetCurrent())

        // 写入剩余计数
        flushCount()

        isRunning = false
        print("⌨️ 击键监听已停止")
    }

    // MARK: - 计数与写入

    /// 递增击键计数（线程安全）
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
