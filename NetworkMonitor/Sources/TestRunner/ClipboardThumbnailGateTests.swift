import Foundation
import NetworkMonitorCore

// MARK: - 缩略图加载闸门（Core 纯状态机）

/// 覆盖增量规格验收标准 B 组：并发上限 / 在途去重 / 额度归还幂等 / reset 清空，
/// 外加失败记忆与非法入参两个异常路径（闸门被一次坏文件卡死是这类闸门的典型事故）。
func runClipboardThumbnailGateTests() {
    print("🧪 Testing Clipboard thumbnail load gate...")

    // 1) 默认并发上限 3；非法上限归一化为默认值（上限 0 等于永久阻塞）
    assertEqual(ClipboardThumbnailLoadGate.defaultMaxConcurrent, 3, "默认并发上限 3")
    var defaults = ClipboardThumbnailLoadGate()
    assertEqual(defaults.maxConcurrent, 3, "默认构造用 3")
    assertEqual(ClipboardThumbnailLoadGate(maxConcurrent: 0).maxConcurrent, 3, "上限 0 归一化为 3")
    assertEqual(ClipboardThumbnailLoadGate(maxConcurrent: -5).maxConcurrent, 3, "上限负数归一化为 3")
    assertEqual(ClipboardThumbnailLoadGate(maxConcurrent: 6).maxConcurrent, 6, "合法上限原样保留")

    // 2) 满额即拒：maxConcurrent = 3 时前 3 个通过、第 4 个返回 false
    var gate = ClipboardThumbnailLoadGate(maxConcurrent: 3)
    assertEqual(gate.activeCount, 0, "初始无在途")
    assertEqual(gate.availableSlots, 3, "初始剩余 3 个额度")
    assertEqual(gate.beginLoad(hash: "aaa"), true, "第 1 个通过")
    assertEqual(gate.beginLoad(hash: "bbb"), true, "第 2 个通过")
    assertEqual(gate.beginLoad(hash: "ccc"), true, "第 3 个通过")
    assertEqual(gate.beginLoad(hash: "ddd"), false, "并发已满时第 4 个返回 false")
    assertEqual(gate.activeCount, 3, "并发满额时在途 3 个")
    assertEqual(gate.inFlightCount, 3, "在途计数与额度占用同源")
    assertEqual(gate.availableSlots, 0, "满额时剩余额度 0")

    // 3) 在途去重：同一 hash 重复 beginLoad 一律返回 false（不重复占额度）
    assertEqual(gate.beginLoad(hash: "aaa"), false, "同 hash 重复 beginLoad 返回 false")
    assertEqual(gate.beginLoad(hash: " aaa "), false, "同 hash 带前后空白仍判为在途")
    assertEqual(gate.activeCount, 3, "重复请求不额外占地")
    var dupGate = ClipboardThumbnailLoadGate(maxConcurrent: 5)
    assertEqual(dupGate.beginLoad(hash: "same"), true, "额度未满时首次通过")
    assertEqual(dupGate.beginLoad(hash: "same"), false, "同一 hash 重复请求返回 false")
    assertEqual(dupGate.activeCount, 1, "重复请求不虚增在途数")

    // 4) finishLoad 归还额度，且重复 finish 幂等
    assertEqual(gate.isInFlight(hash: "aaa"), true, "finish 前该 hash 在途")
    gate.finishLoad(hash: "aaa")
    assertEqual(gate.isInFlight(hash: "aaa"), false, "finish 后该 hash 已不在途")
    assertEqual(gate.activeCount, 2, "finish 后额度归还（在途 2）")
    assertEqual(gate.availableSlots, 1, "finish 后剩余额度 1")
    assertEqual(gate.beginLoad(hash: "ddd"), true, "归还后新请求通过")
    gate.finishLoad(hash: "aaa")
    assertEqual(gate.activeCount, 3, "重复 finish 幂等（不会误删别人的额度）")
    gate.finishLoad(hash: "never-begun")
    assertEqual(gate.activeCount, 3, "finish 未登记的 hash 无副作用")
    assertEqual(gate.isInFlight(hash: "never-begun"), false, "finish 不会给未登记的 hash 造出在途")

    // 5) 失败不再由闸门记忆：解码失败后归还额度，同一 hash 可以重新登记
    //    （「失败能重试几次」的唯一判据是 ClipboardThumbnailRetryPolicy，闸门只管并发与去重）
    gate.finishLoad(hash: "ccc")
    assertEqual(gate.beginLoad(hash: "ccc"), true, "归还额度后同一 hash 可重新登记")
    gate.finishLoad(hash: "ccc")
    assertEqual(gate.beginLoad(hash: "eee"), true, "其他 hash 不受影响")
    assertEqual(gate.activeCount, 3, "登记后额度重新占满（bbb/ddd/eee）")

    // 6) reset 清空在途与计数（下次允许重新尝试）
    gate.reset()
    assertEqual(gate.activeCount, 0, "reset 后无在途")
    assertEqual(gate.inFlightCount, 0, "reset 后在途计数清零")
    assertEqual(gate.availableSlots, 3, "reset 后额度全额可用")
    assertEqual(gate.beginLoad(hash: "ccc"), true, "reset 后任意 hash 都允许重新尝试")

    // 7) 非法入参：空白 hash 一律拒绝（空键会让所有条目共用一个额度槽）
    var blankGate = ClipboardThumbnailLoadGate(maxConcurrent: 3)
    assertEqual(blankGate.beginLoad(hash: ""), false, "空 hash 拒绝")
    assertEqual(blankGate.beginLoad(hash: "   "), false, "纯空白 hash 拒绝")
    assertEqual(blankGate.activeCount, 0, "非法入参不占额度")

    // 8) 缩略图就绪事件：post 时带上 contentHash，订阅方据此定位重绘卡片
    var receivedHash: String?
    let observer = NotificationCenter.default.addObserver(
        forName: AppEvents.clipboardThumbnailReady, object: nil, queue: nil
    ) { notification in
        receivedHash = notification.userInfo?[AppEvents.clipboardThumbnailHashKey] as? String
    }
    AppEvents.postClipboardThumbnailReady(contentHash: "hash-ready")
    NotificationCenter.default.removeObserver(observer)
    assertEqual(receivedHash, "hash-ready", "clipboardThumbnailReady 携带 contentHash")

    // 空白 hash 不发通知（避免订阅方收到无法定位的广播）
    var blankReceived = false
    let blankObserver = NotificationCenter.default.addObserver(
        forName: AppEvents.clipboardThumbnailReady, object: nil, queue: nil
    ) { _ in
        blankReceived = true
    }
    AppEvents.postClipboardThumbnailReady(contentHash: "  ")
    NotificationCenter.default.removeObserver(blankObserver)
    assertEqual(blankReceived, false, "空白 hash 不发布缩略图就绪事件")

    print("✅ Clipboard 缩略图加载闸门 works")
}
