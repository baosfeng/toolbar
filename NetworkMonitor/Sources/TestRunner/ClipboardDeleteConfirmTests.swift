import Foundation
import NetworkMonitorCore

// MARK: - 剪贴板删除二次确认（设计规格 2.3-2 / 验收 C 组）

/// 覆盖规格「增量 C」的确认状态机：首次需确认 / 窗口内二次可执行 / 超窗失效 /
/// 不同对象打断 / 单条与清空互不串味 / 显式清理后回到确认态。
///
/// 状态机是 Core 纯类型（无计时器、无 AppKit），时间由调用方传入，因此可直接断言。
func runClipboardDeleteConfirmTests() {
    print("🧪 Testing Clipboard delete confirmation...")
    runFirstRequestNeedsConfirmTests()
    runSecondRequestExecutesTests()
    runWindowExpiryTests()
    runDifferentIdentifierTests()
    runIndependentStatesTests()
    runResetTests()
    runPendingQueryTests()
    print("✅ Clipboard 删除二次确认（首次 / 二次 / 超窗 / 打断 / 互不串味 / 清理）works")
}

/// 首次请求一律进入确认态
private func runFirstRequestNeedsConfirmTests() {
    var confirm = ClipboardDeleteConfirm()
    let id = UUID()
    assertEqual(confirm.requestDelete(id: id, now: 100), true, "首次请求需确认")
    assertEqual(confirm.hasPending, true, "首次请求登记待确认")
    assertEqual(confirm.pendingID, id, "登记的是本次请求的标识")
}

/// 窗口内同一标识二次请求直接放行并清理登记
private func runSecondRequestExecutesTests() {
    var confirm = ClipboardDeleteConfirm()
    let id = UUID()
    assertEqual(confirm.requestDelete(id: id, now: 100), true, "首次需确认")
    assertEqual(confirm.requestDelete(id: id, now: 100.5), false, "窗口内二次请求可执行")
    assertEqual(confirm.hasPending, false, "放行后登记已清理")

    var edge = ClipboardDeleteConfirm()
    assertEqual(edge.requestDelete(id: id, now: 100), true, "边界用例首次需确认")
    assertEqual(edge.requestDelete(id: id, now: 102.0), false, "恰好等于窗口仍算窗口内")
}

/// 超过窗口后重新进入确认态
private func runWindowExpiryTests() {
    var confirm = ClipboardDeleteConfirm()
    let id = UUID()
    assertEqual(confirm.requestDelete(id: id, now: 100), true, "首次需确认")
    assertEqual(confirm.requestDelete(id: id, now: 102.5), true, "超窗后重新进入确认态")
    assertEqual(confirm.pendingID, id, "超窗后以本次时刻重新登记")

    var narrow = ClipboardDeleteConfirm(window: 0.5)
    assertEqual(narrow.requestDelete(id: id, now: 10), true, "窄窗口首次需确认")
    assertEqual(narrow.requestDelete(id: id, now: 10.8), true, "窄窗口超窗重新确认")

    var clockBack = ClipboardDeleteConfirm()
    assertEqual(clockBack.requestDelete(id: id, now: 100), true, "回拨用例首次需确认")
    assertEqual(clockBack.requestDelete(id: id, now: 99), true, "时刻回拨按超窗处理，不误判为可执行")
}

/// 不同标识打断上一次确认
private func runDifferentIdentifierTests() {
    var confirm = ClipboardDeleteConfirm()
    let first = UUID(), second = UUID()
    assertEqual(confirm.requestDelete(id: first, now: 100), true, "第一条需确认")
    assertEqual(confirm.requestDelete(id: second, now: 100.2), true, "不同标识打断确认，需重新确认")
    assertEqual(confirm.requestDelete(id: second, now: 100.4), false, "打断后同一标识二次可执行")
}

/// 单条删除与清空历史各持一份状态，互不串味
private func runIndependentStatesTests() {
    var single = ClipboardDeleteConfirm()
    var bulk = ClipboardDeleteConfirm()
    let item = UUID()
    let bulkKey = UUID()
    assertEqual(single.requestDelete(id: item, now: 100), true, "单条首次需确认")
    assertEqual(bulk.requestDelete(id: bulkKey, now: 100), true, "清空首次需确认（不因单条登记而放行）")
    assertEqual(single.requestDelete(id: item, now: 100.3), false, "单条窗口内二次可执行")
    assertEqual(bulk.hasPending, true, "清空状态不受单条放行影响")
    assertEqual(bulk.requestDelete(id: bulkKey, now: 100.6), false, "清空二次可执行")
}

/// 显式清理后再次请求回到确认态
private func runResetTests() {
    var confirm = ClipboardDeleteConfirm()
    let id = UUID()
    assertEqual(confirm.requestDelete(id: id, now: 100), true, "首次需确认")
    assertEqual(confirm.requestDelete(id: id, now: 100.2), false, "二次可执行")
    confirm.reset()
    assertEqual(confirm.hasPending, false, "清理后无待确认登记")
    assertEqual(confirm.requestDelete(id: id, now: 100.4), true, "清理后再次请求回到确认态")
}

/// 待确认查询：窗口内有效、超窗失效
private func runPendingQueryTests() {
    var confirm = ClipboardDeleteConfirm()
    let id = UUID()
    assertEqual(confirm.isPending(at: 100), false, "未请求时无待确认")
    assertEqual(confirm.requestDelete(id: id, now: 100), true, "首次需确认")
    assertEqual(confirm.isPending(at: 100.5), true, "窗口内待确认有效")
    assertEqual(confirm.isPending(at: 102.5), false, "超窗待确认失效")
    confirm.reset()
    assertEqual(confirm.isPending(at: 100.6), false, "清理后待确认失效")
}
