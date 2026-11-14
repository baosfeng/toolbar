import Foundation
import NetworkMonitorCore

// MARK: - 队列排队等待计时（观测埋点）

/// 录制日志：给「只靠日志可见」的行为（队列等待 / 看门狗）做断言
final class RecordingLogger: LoggingService, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func log(_ level: LogLevel, _ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }
}

func runDatabaseQueueWaitTests() {
    print("🧪 Testing DB 队列排队等待计时...")
    let recorder = RecordingLogger()
    let queue = DatabaseQueue(label: "test.databaseQueue", thresholdMs: 20, logger: { recorder })

    // 快路径：无排队 → 不记日志
    assertEqual(queue.sync { 42 }, 42, "sync 原样返回闭包结果")
    assertEqual(recorder.all.isEmpty, true, "无排队时不记日志")

    // 慢路径：先让另一个块占住队列 300 ms，再去 sync → 排队等待 > 20 ms 记一条
    let entered = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        queue.sync {
            entered.signal()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
    assertEqual(entered.wait(timeout: .now() + 5) == .success, true, "占位块已进入队列")
    assertEqual(queue.sync { 7 }, 7, "排队后的 sync 仍返回正确结果")
    assertEqual(recorder.all.count, 1, "排队等待超阈值记一条")
    assertContains(recorder.all[0], "DB 队列排队等待", "日志指出排队等待")
    assertContains(recorder.all[0], "执行", "日志同时给出执行时长")
    assertContains(recorder.all[0], "runDatabaseQueueWaitTests", "日志带调用方函数名")
}
